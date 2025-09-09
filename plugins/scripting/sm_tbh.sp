/*************************************************
 * L4D2 Throwable Boost Unlock Assist (FORCE mode)
 * Author: IchinaZiru
 * Requires: SourceMod 1.11+, SDKTools, SDKHooks
 * Build: spcomp l4d2_tbu_assist.sp
 * 
 * ALWAYS auto-AFK when a diagonal-up acceleration spike is detected,
 * regardless of the player's current/sustained speed.
 * Detection uses only: derivative (delta speed) + angle window + cooldown.
 * 
 * Commands:
 * Chat: !tbu  (toggle for self)
 * Console: sm_tbu  (toggle for self)
 * AFK -> hold_ms -> TakeOver via SDKCall
 * 
 * Data file
 * Signatures loaded from gamedata/st_signs.txt  (keys: GoAwayFromKeyboard, TakeOverBot)
 * Reference file URL : https://forums.alliedmods.net/showthread.php?p=2574530
 **************************************************/

#include <string>
#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

public Plugin myinfo = {
    name        = "L4D2 Throwable Boost Unlock Assist",
    author      = "IchinaZiru",
    description = "Force auto-AFK on diagonal-up acceleration spike (ignore base speed).",
    version     = "1.1.0",
    url         = "https://github.com/IchinaZiru/tas4l4d2"
};

// ----- ConVars (FORCE mode) -----
ConVar gCvarEnable;
ConVar gCvarVelDeltaMin;   // minimal sudden jump (noise filter)
ConVar gCvarAngMin;        // diagonal-up lower bound (deg)
ConVar gCvarAngMax;        // diagonal-up upper bound (deg)
ConVar gCvarCooldownMs;    // cooldown between AFK firings (ms)
ConVar gCvarAfkHoldMs;     // AFK hold time before TakeOver (ms)
ConVar gCvarSampleSec;     // sampling interval (sec)

// Cached
bool  g_bEnabled;
float g_fVelDeltaMin;
float g_fAngMin, g_fAngMax;
float g_fCooldownMs, g_fAfkHoldMs, g_fSampleSec;

// Per-client state
bool  g_bClientToggle[MAXPLAYERS + 1]; // per-player ON/OFF
float g_fPrevSpeed   [MAXPLAYERS + 1];
float g_fLastFireAt  [MAXPLAYERS + 1]; // game time (sec)

Handle g_hSampleTimer = INVALID_HANDLE;

// SDKCalls (from st_signs.txt)
Handle g_hGameConf     = INVALID_HANDLE;
Handle g_hSDK_GoAFK    = INVALID_HANDLE; // CTerrorPlayer::GoAwayFromKeyboard()
Handle g_hSDK_TakeOver = INVALID_HANDLE; // CTerrorPlayer::TakeOverBot(bool)

// ----- Utils -----
#if defined DEG
    #undef DEG
#endif

static const float RAD2DEG = 57.295779513;

#define DEG(%1) ((%1) * RAD2DEG)


stock bool IsValidHumanSurvivor(int client)
{
    return (1 <= client <= MaxClients)
        && IsClientInGame(client)
        && !IsFakeClient(client)
        && IsPlayerAlive(client)
        && GetClientTeam(client) == 2;
}

stock float GetPlayerSpeed(int client)
{
    float v[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", v);
    return SquareRoot(v[0]*v[0] + v[1]*v[1] + v[2]*v[2]);
}

stock float GetVelAngleDeg(int client)
{
    float v[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", v);
    float horiz = SquareRoot(v[0]*v[0] + v[1]*v[1]);
    if (horiz < 0.001) return 90.0;
    float ang = ArcTangent2(v[2], horiz);
    return DEG(ang);
}

stock void FireAFKSequence(int client, float holdMs)
{
    if (g_hSDK_GoAFK == INVALID_HANDLE || g_hSDK_TakeOver == INVALID_HANDLE)
    {
        PrintToChat(client, "[TBU] AFK SDKCall not ready (check st_signs.txt).");
        return;
    }

    // 1) Go AFK immediately
    SDKCall(g_hSDK_GoAFK, client);

    // 2) TakeOver after holdMs
    int serial = GetClientSerial(client);
    CreateTimer(holdMs / 1000.0, Timer_TakeOver, serial, TIMER_FLAG_NO_MAPCHANGE);
}

public Action Timer_TakeOver(Handle timer, any serial)
{
    int client = GetClientFromSerial(serial);
    if (client && IsClientInGame(client) && IsPlayerAlive(client))
    {
        // true: human take over
        SDKCall(g_hSDK_TakeOver, client, true);
    }
    return Plugin_Stop;
}

// ----- Core sampler (FORCE): derivative + angle + cooldown -----
public Action Timer_Sampler(Handle timer, any data)
{
    if (!g_bEnabled) return Plugin_Continue;

    float now = GetGameTime();

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsValidHumanSurvivor(i)) continue;
        if (!g_bClientToggle[i])     continue;

        float s  = GetPlayerSpeed(i);
        float ds = s - g_fPrevSpeed[i];
        float a  = GetVelAngleDeg(i);

        bool okDelta = (ds >= g_fVelDeltaMin);                // sudden jump only
        bool okAngle = (a  >= g_fAngMin && a <= g_fAngMax);   // ~45° diagonal-up
        bool okCD    = (now - g_fLastFireAt[i] >= g_fCooldownMs / 1000.0);

        if (okDelta && okAngle && okCD)
        {
            g_fLastFireAt[i] = now;
            FireAFKSequence(i, g_fAfkHoldMs);
            PrintCenterText(i, "AFK AUTO (Δvel~%.0f, ang~%.0f°)", ds, a);
        }

        g_fPrevSpeed[i] = s;
    }

    return Plugin_Continue;
}

// ----- Chat / Console -----
public Action Cmd_SayHook(int client, const char[] command, int argc)
{
    if (client <= 0 || !IsClientInGame(client)) return Plugin_Continue;

    char text[256];
    GetCmdArgString(text, sizeof(text));
    StripQuotes(text);      // " ... " をまとめて除去
    TrimString(text);       // 前後の空白除去

    if (StrEqual(text, "!tbu", false)) {
        g_bClientToggle[client] = !g_bClientToggle[client];
        PrintToChat(client, "[TBU] %s", g_bClientToggle[client] ? "ON" : "OFF");
        return Plugin_Handled;
    }
    return Plugin_Continue;
}

public Action Cmd_TbuToggle(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client))
    {
        ReplyToCommand(client, "[TBU] In-game players only.");
        return Plugin_Handled;
    }

    g_bClientToggle[client] = !g_bClientToggle[client];
    ReplyToCommand(client, "[TBU] %s", g_bClientToggle[client] ? "ON" : "OFF");
    return Plugin_Handled;
}

// ----- ConVar cache -----
void CacheConVars()
{
    g_bEnabled      = gCvarEnable.BoolValue;
    g_fVelDeltaMin  = gCvarVelDeltaMin.FloatValue;
    g_fAngMin       = gCvarAngMin.FloatValue;
    g_fAngMax       = gCvarAngMax.FloatValue;
    g_fCooldownMs   = gCvarCooldownMs.FloatValue;
    g_fAfkHoldMs    = gCvarAfkHoldMs.FloatValue;
    g_fSampleSec    = gCvarSampleSec.FloatValue;

    if (g_hSampleTimer != INVALID_HANDLE)
    {
        CloseHandle(g_hSampleTimer);
        g_hSampleTimer = INVALID_HANDLE;
    }
    g_hSampleTimer = CreateTimer(g_fSampleSec, Timer_Sampler, _, TIMER_REPEAT | TIMER_FLAG_NO_MAPCHANGE);
}

public void OnConVarChanged(ConVar c, const char[] o, const char[] n)
{
    CacheConVars();
}

// ----- SDKCalls init (load st_signs) -----
bool SetupSDKCalls()
{
    // Read "st_signs.txt" (without .txt in API)
    g_hGameConf = LoadGameConfigFile("st_signs");
    if (g_hGameConf == INVALID_HANDLE)
    {
        LogError("[TBU] Failed to load gamedata: st_signs.txt");
        return false;
    }

    // CTerrorPlayer::GoAwayFromKeyboard()
    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "GoAwayFromKeyboard");
    g_hSDK_GoAFK = EndPrepSDKCall();
    if (g_hSDK_GoAFK == INVALID_HANDLE)
    {
        LogError("[TBU] Failed to prep GoAwayFromKeyboard (check st_signs.txt)");
        return false;
    }

    // CTerrorPlayer::TakeOverBot(bool)
    StartPrepSDKCall(SDKCall_Player);
    PrepSDKCall_SetFromConf(g_hGameConf, SDKConf_Signature, "TakeOverBot");
    PrepSDKCall_AddParameter(SDKType_Bool, SDKPass_Plain);
    g_hSDK_TakeOver = EndPrepSDKCall();
    if (g_hSDK_TakeOver == INVALID_HANDLE)
    {
        LogError("[TBU] Failed to prep TakeOverBot (check st_signs.txt)");
        return false;
    }

    return true;
}

// ----- Lifecycle -----
public void OnPluginStart()
{
    // FORCE defaults tuned for throwable boost unlock
    gCvarEnable       = CreateConVar("sm_tbu_enable",      "1",    "Master switch (0/1).", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    gCvarVelDeltaMin  = CreateConVar("sm_tbu_vel_delta",   "260",  "Required sudden speed jump (current - previous).");
    gCvarAngMin       = CreateConVar("sm_tbu_ang_min",     "35",   "Min angle (deg) for diagonal-up window.");
    gCvarAngMax       = CreateConVar("sm_tbu_ang_max",     "58",   "Max angle (deg) for diagonal-up window.");
    gCvarCooldownMs   = CreateConVar("sm_tbu_cooldown_ms", "350",  "Cooldown between AFK firings (ms).");
    gCvarAfkHoldMs    = CreateConVar("sm_tbu_hold_ms",     "60",   "AFK hold time before TakeOver (ms).");
    gCvarSampleSec    = CreateConVar("sm_tbu_sample_sec",  "0.01", "Sampler interval in seconds.");

    AutoExecConfig(true, "l4d2_tbu_assist_force");

    // Commands
    RegConsoleCmd("sm_tbu", Cmd_TbuToggle);
    AddCommandListener(Cmd_SayHook, "say");
    AddCommandListener(Cmd_SayHook, "say_team");

    // SDKCalls
    if (!SetupSDKCalls())
    {
        SetFailState("[TBU] SDKCalls not ready. Ensure gamedata/st_signs.txt exists and has required signatures.");
        return;
    }

    // init per-client
    for (int i = 1; i <= MaxClients; i++)
    {
        g_bClientToggle[i] = true;  // default ON
        g_fPrevSpeed[i]    = 0.0;
        g_fLastFireAt[i]   = 0.0;
    }

    CacheConVars();

    // ConVar change hooks
    HookConVarChange(gCvarEnable,      OnConVarChanged);
    HookConVarChange(gCvarVelDeltaMin, OnConVarChanged);
    HookConVarChange(gCvarAngMin,      OnConVarChanged);
    HookConVarChange(gCvarAngMax,      OnConVarChanged);
    HookConVarChange(gCvarCooldownMs,  OnConVarChanged);
    HookConVarChange(gCvarAfkHoldMs,   OnConVarChanged);
    HookConVarChange(gCvarSampleSec,   OnConVarChanged);

    PrintToServer("[TBU] FORCE mode loaded (st_signs).");
}

public void OnClientPutInServer(int client)
{
    g_bClientToggle[client] = true;
    g_fPrevSpeed[client]    = 0.0;
    g_fLastFireAt[client]   = 0.0;
}