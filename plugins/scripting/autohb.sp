/*************************************************
 * l4d2_autohunter_mr.sp
 *  - L4D2: Hunter movement Record/Play (MR) + Auto Hunter Boost (ETA-based)
 *
 * Commands:
 *   sm_hmr_rec                               : Record movement of the nearest Hunter to the configured MR file.
 *   sm_hmr_play                              : Play back movement for the nearest Hunter from the MR file.
 *   sm_autohb                                : Toggle Auto Hunter Boost on/off.
 *   sm_hbtune <shove> <jump> <advance>       : Adjust shove lead, jump lead, and advance timing values in real time.
 *
 * Data file (auto-created/updated):
 *   cfg/sm_server/data/l4d2_transit_pairs.cfg
 **************************************************/

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#pragma semicolon 1
#pragma newdecls required

#define TEAM_SURV 2
#define TEAM_INF  3
#define Z_HUNTER  3

// --- ConVars ---
ConVar       gCvarEnable, gCvarShoveLead, gCvarJumpLead, gCvarAdvance, gCvarClosingMin, gCvarRange, gCvarFacingMin, gCvarCD, gCvarFile;

static float g_nextShove[MAXPLAYERS + 1];
static float g_nextJump[MAXPLAYERS + 1];
static float g_cdUntil[MAXPLAYERS + 1];

public Plugin myinfo =
{
    name        = "L4D2 AutoHunter MR + Boost",
    author      = "IchinaZiru",
    description = "Record/Play Hunter with MR, then auto shove+jump to trigger Hunter boost",
    version     = "0.1 Beta",
    url         = "https://github.com/IchinaZiru/tas4l4d"
};

public void OnPluginStart()
{
    gCvarEnable     = CreateConVar("ahb_enable", "1", "Enable Auto Hunter Boost");
    gCvarShoveLead  = CreateConVar("ahb_shove_lead", "0.110", "Lead time (sec) for shove before ETA");
    gCvarJumpLead   = CreateConVar("ahb_jump_lead", "0.070", "Lead time (sec) for jump before ETA");
    gCvarAdvance    = CreateConVar("ahb_const_advance", "0.060", "Advance offset for ping/tick (sec)");
    gCvarClosingMin = CreateConVar("ahb_closing_min", "350.0", "Min approach speed treated as lunge");
    gCvarRange      = CreateConVar("ahb_range", "1800.0", "Detection range");
    gCvarFacingMin  = CreateConVar("ahb_facing_min", "0.75", "cos(theta) threshold (0..1)");
    gCvarCD         = CreateConVar("ahb_cooldown", "0.25", "Cooldown between schedules (sec)");
    gCvarFile       = CreateConVar("ahb_mr_file", "movement_hunter", "MR file name");

    RegAdminCmd("sm_hmr_rec", Cmd_MR_Record, ADMFLAG_GENERIC, "Record nearest hunter to ahb_mr_file");
    RegAdminCmd("sm_hmr_play", Cmd_MR_Play, ADMFLAG_GENERIC, "Play nearest hunter from ahb_mr_file");
    RegAdminCmd("sm_autohb", Cmd_Toggle, ADMFLAG_GENERIC, "Toggle Auto HB");
    RegAdminCmd("sm_hbtune", Cmd_Tune, ADMFLAG_GENERIC, "Tune shove/jump/advance timings");

    // Inject buttons via OnPlayerRunCmd
    HookUserMessage(GetUserMessageId("VGUIMenu"), DummyUM, true);    // No-op: ensures at least one early hook on some servers
    for (int i = 1; i <= MaxClients; i++)
        if (IsClientInGame(i)) SDKHook(i, SDKHook_OnPlayerRunCmd, OnPlayerRunCmd);
}

public void OnClientPutInServer(int client)
{
    SDKHook(client, SDKHook_OnPlayerRunCmd, OnPlayerRunCmd);
    g_nextShove[client] = g_nextJump[client] = g_cdUntil[client] = 0.0;
}

public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float vel[3], float angles[3], int &weapon)
{
    if (!gCvarEnable.BoolValue) return Plugin_Continue;
    if (!IsClientInGame(client) || !IsPlayerAlive(client)) return Plugin_Continue;
    if (GetClientTeam(client) != TEAM_SURV) return Plugin_Continue;

    float now = GetGameTime();

    // While in cooldown, only fire scheduled inputs
    if (now >= g_nextShove[client] && g_nextShove[client] > 0.0)
    {
        buttons |= IN_ATTACK2;
        g_nextShove[client] = 0.0;
    }
    if (now >= g_nextJump[client] && g_nextJump[client] > 0.0)
    {
        buttons |= IN_JUMP;
        g_nextJump[client] = 0.0;
    }

    // Create new schedule
    if (now >= g_cdUntil[client])
    {
        int hunter = FindNearestIncomingHunter(client);
        if (hunter > 0)
        {
            float eta = EstimateETA(client, hunter);
            if (eta >= 0.0)
            {
                float shoveLead     = gCvarShoveLead.FloatValue;
                float jumpLead      = gCvarJumpLead.FloatValue;
                float cd            = gCvarCD.FloatValue;

                g_nextShove[client] = now + Max(0.0, eta - shoveLead);
                g_nextJump[client]  = now + Max(0.0, eta - jumpLead);
                g_cdUntil[client]   = now + cd;
                // PrintToChat(client, "[AHB] ETA=%.3f shove=%.3f jump=%.3f", eta, g_nextShove[client]-now, g_nextJump[client]-now);
            }
        }
    }
    return Plugin_Continue;
}

// --- Find the nearest Hunter that is clearly lunging toward the survivor ---
int FindNearestIncomingHunter(int client)
{
    float bestETA = 99999.0;
    int   bestEnt = -1;
    float posC[3];
    GetClientAbsOrigin(client, posC);

    float range      = gCvarRange.FloatValue;
    float minCos     = gCvarFacingMin.FloatValue;
    float minClosing = gCvarClosingMin.FloatValue;

    for (int i = 1; i <= MaxClients; i++)
    {
        if (!IsClientInGame(i) || !IsPlayerAlive(i)) continue;
        if (GetClientTeam(i) != TEAM_INF) continue;
        if (GetZombieClass(i) != Z_HUNTER) continue;

        // Airborne check (approx). For precise ground state, prefer m_hGroundEntity via DHooks/Left4DHooks.
        if (IsOnGround(i)) continue;

        float posH[3];
        GetClientAbsOrigin(i, posH);
        float velH[3];
        GetEntPropVector(i, Prop_Data, "m_vecVelocity", velH);

        float toMe[3];
        toMe[0]    = posC[0] - posH[0];
        toMe[1]    = posC[1] - posH[1];
        toMe[2]    = 0.0;

        float dist = SquareRoot(toMe[0] * toMe[0] + toMe[1] * toMe[1]);
        if (dist > range) continue;

        Normalize2D(velH);
        Normalize2D(toMe);
        float facing = (velH[0] * toMe[0] + velH[1] * toMe[1]);    // cos(theta)
        if (facing < minCos) continue;

        float speed = GetSpeed2D(i);
        if (speed < minClosing) continue;

        float eta = dist / speed - gCvarAdvance.FloatValue;
        if (eta < 0.0) eta = 0.0;

        if (eta < bestETA)
        {
            bestETA = eta;
            bestEnt = i;
        }
    }
    return (bestEnt > 0) ? bestEnt : -1;
}

float EstimateETA(int client, int hunter)
{
    float posC[3], posH[3], velH[3];
    GetClientAbsOrigin(client, posC);
    GetClientAbsOrigin(hunter, posH);
    GetEntPropVector(hunter, Prop_Data, "m_vecVelocity", velH);

    float toMe[3];
    toMe[0]     = posC[0] - posH[0];
    toMe[1]     = posC[1] - posH[1];
    toMe[2]     = 0.0;

    float dist  = SquareRoot(toMe[0] * toMe[0] + toMe[1] * toMe[1]);
    float speed = GetSpeed2D(hunter);
    if (speed <= 1.0) return -1.0;

    float eta = dist / speed - gCvarAdvance.FloatValue;
    return (eta < 0.0 ? 0.0 : eta);
}

// --- Utilities ---
int GetZombieClass(int client)
{
    // Use Left4DHooks API if available; otherwise fall back to common props.
    int zc = GetEntProp(client, Prop_Send, "m_zombieClass", 1);
    if (zc == 0) zc = GetEntProp(client, Prop_Send, "m_iPlayerType", 1);
    return zc;
}
bool IsOnGround(int client)
{
    // Approximation: check ground flag (and implicitly near-zero Z speed in practice).
    int flags = GetEntProp(client, Prop_Send, "m_fFlags");
    return (flags & FL_ONGROUND) != 0;
}
float GetSpeed2D(int client)
{
    float v[3];
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", v);
    return SquareRoot(v[0] * v[0] + v[1] * v[1]);
}
void Normalize2D(float v[3])
{
    float L = SquareRoot(v[0] * v[0] + v[1] * v[1]);
    if (L > 0.0001)
    {
        v[0] /= L;
        v[1] /= L;
    }
    else {
        v[0] = 0.0;
        v[1] = 0.0;
    }
}

// --- MR integration (cvar-based; replace with ST_MR* calls if present) ---
public Action Cmd_MR_Record(int client, int args)
{
    int hunter = FindNearestIncomingHunter(client);
    if (hunter <= 0)
    {
        ReplyToCommand(client, "[AHB] no hunter nearby");
        return Plugin_Handled;
    }

    char file[128];
    gCvarFile.GetString(file, sizeof file);
    ServerCommand("st_mr_force_file %s; st_mr_record 1", file);
    ReplyToCommand(client, "[AHB] MR record: %s", file);
    return Plugin_Handled;
}

public Action Cmd_MR_Play(int client, int args)
{
    int hunter = FindNearestIncomingHunter(client);
    if (hunter <= 0)
    {
        ReplyToCommand(client, "[AHB] no hunter nearby");
        return Plugin_Handled;
    }

    char file[128];
    gCvarFile.GetString(file, sizeof file);
    ServerCommand("st_mr_force_file %s; st_mr_play %d", file, GetClientUserId(hunter));
    ReplyToCommand(client, "[AHB] MR play: %s -> hunter userid %d", file, GetClientUserId(hunter));
    return Plugin_Handled;
}

public Action Cmd_Toggle(int client, int args)
{
    gCvarEnable.BoolValue = !gCvarEnable.BoolValue;
    ReplyToCommand(client, "[AHB] %s", gCvarEnable.BoolValue ? "ON" : "OFF");
    return Plugin_Handled;
}

public Action Cmd_Tune(int client, int args)
{
    if (args >= 1)
    {
        char s[32];
        GetCmdArg(1, s, sizeof s);
        gCvarShoveLead.FloatValue = StringToFloat(s);
    }
    if (args >= 2)
    {
        char s[32];
        GetCmdArg(2, s, sizeof s);
        gCvarJumpLead.FloatValue = StringToFloat(s);
    }
    if (args >= 3)
    {
        char s[32];
        GetCmdArg(3, s, sizeof s);
        gCvarAdvance.FloatValue = StringToFloat(s);
    }
    ReplyToCommand(client, "[AHB] shove=%.3f jump=%.3f adv=%.3f",
                   gCvarShoveLead.FloatValue, gCvarJumpLead.FloatValue, gCvarAdvance.FloatValue);
    return Plugin_Handled;
}

// No-op user message hook (placeholder)
public Action DummyUM(UserMsg msg_id, bf_read msg, const int[] players, int playersNum, bool reliable, bool init) { return Plugin_Continue; }
