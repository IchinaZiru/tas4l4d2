#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>

public Plugin myinfo =
{
    name        = "TAS Recorder (txt logger)",
    author      = "IchinaZiru",
    description = "Record real in-game movement into a text format per frame",
    version     = "0.1.0",
    url         = "https://github.com/IchinaZiru/tas4l4d2"
};

// ====== Per-client state ======
bool   g_bRec[MaxClients + 1];
char   g_FilePath[MaxClients + 1][PLATFORM_MAX_PATH];
Handle g_hFile[MaxClients + 1];

// ====== Commands ======
public void OnPluginStart()
{
    RegConsoleCmd("sm_recstart", Cmd_RecStart);
    RegConsoleCmd("sm_recstop", Cmd_RecStop);
    PrintToServer("[TAS] tas_recorder loaded.");
}

public void OnMapEnd()
{
    // Safety: close any remaining files
    for (int i = 1; i <= MaxClients; i++)
    {
        StopRecording(i, false);
    }
}

public void OnClientDisconnect(int client)
{
    StopRecording(client, false);
}

// ====== Command Implementations ======
public Action Cmd_RecStart(int client, int args)
{
    if (!IsValidLiveClient(client))
    {
        ReplyToCommand(client, "[TAS] You must be alive in-game.");
        return Plugin_Handled;
    }

    char name[128];
    if (args >= 1)
    {
        GetCmdArg(1, name, sizeof(name));
    }
    else {
        // Auto name: YYYYMMDD_HHMMSS
        FormatTime(name, sizeof(name), "%Y%m%d_%H%M%S", GetTime());
    }

    if (!StartRecording(client, name))
    {
        ReplyToCommand(client, "[TAS] Failed to start recording.");
        return Plugin_Handled;
    }

    ReplyToCommand(client, "[TAS] Recording started: %s", g_FilePath[client]);
    return Plugin_Handled;
}

public Action Cmd_RecStop(int client, int args)
{
    if (!g_bRec[client])
    {
        ReplyToCommand(client, "[TAS] Not recording.");
        return Plugin_Handled;
    }

    StopRecording(client, true);
    ReplyToCommand(client, "[TAS] Recording stopped: %s", g_FilePath[client]);
    return Plugin_Handled;
}

// ====== Core ======
bool StartRecording(int client, const char[] name)
{
    if (g_bRec[client])
    {
        StopRecording(client, false);
    }

    // Build directory: addons/sourcemod/data/movements/<map>/
    char map[64];
    GetCurrentMap(map, sizeof(map));

    char dir[PLATFORM_MAX_PATH];
    BuildPath(Path_SM, dir, sizeof(dir), "data/movements/%s", map);
    CreateDirectoryRecursive(dir);

    // Build file path
    BuildPath(Path_SM, g_FilePath[client], sizeof(g_FilePath[]), "data/movements/%s/%s.txt", map, name);

    // Open file
    g_hFile[client] = OpenFile(g_FilePath[client], "w");
    if (g_hFile[client] == INVALID_HANDLE)
    {
        return false;
    }

    // Header: Origin / Angles / Velocity
    float pos[3], ang[3], vel[3];
    GetClientAbsOrigin(client, pos);
    GetClientEyeAngles(client, ang);
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);

    WriteHeader(client, pos, ang, vel);

    g_bRec[client] = true;
    return true;
}

void StopRecording(int client, bool announce)
{
    if (!g_bRec[client]) return;

    g_bRec[client] = false;

    if (g_hFile[client] != INVALID_HANDLE)
    {
        CloseHandle(g_hFile[client]);
        g_hFile[client] = INVALID_HANDLE;
    }

    if (announce)
        PrintToServer("[TAS] Saved: %s (client %d)", g_FilePath[client], client);

    g_FilePath[client][0] = '\0';
}

void WriteHeader(int client, const float pos[3], const float ang[3], const float vel[3])
{
    char line[256];

    FormatEx(line, sizeof(line), "Origin: %.3f %.3f %.3f", pos[0], pos[1], pos[2]);
    WriteFileLine(g_hFile[client], "%s", line);

    // roll is almost always 0 in L4D2
    FormatEx(line, sizeof(line), "Angles: %.3f %.3f %.3f", ang[0], ang[1], 0.0);
    WriteFileLine(g_hFile[client], "%s", line);

    FormatEx(line, sizeof(line), "Velocity: %.3f %.3f %.3f", vel[0], vel[1], vel[2]);
    WriteFileLine(g_hFile[client], "%s", line);
}

// Create nested directories if not exist
void CreateDirectoryRecursive(const char[] path)
{
    // CreateDirectory returns true on success; ignore result and try parent chain.
    char temp[PLATFORM_MAX_PATH];
    strcopy(temp, sizeof(temp), path);

    // Normalize slashes
    ReplaceString(temp, sizeof(temp), "\\", "/");

    int len = strlen(temp);
    for (int i = 1; i < len; i++)
    {
        if (temp[i] == '/')
        {
            temp[i] = '\0';
            CreateDirectory(temp, 511);
            temp[i] = '/';
        }
    }
    CreateDirectory(temp, 511);
}

// ====== Per-frame capture ======
public Action OnPlayerRunCmd(int client, int &buttons, int &impulse, float velWish[3],
                      float ang[3], int &weapon, int &subtype, int &cmdnum,
                      int &tickcount, int &seed, int mouse[2])
{
    if (!g_bRec[client] || !IsClientInGame(client) || !IsPlayerAlive(client) || g_hFile[client] == INVALID_HANDLE)
        return Plugin_Continue;

    // Actual state
    float pos[3], eye[3], vel[3];
    GetClientAbsOrigin(client, pos);
    GetClientEyeAngles(client, eye);
    GetEntPropVector(client, Prop_Data, "m_vecVelocity", vel);

    // buttons : pitch : yaw : roll : posX,posY,posZ : velX,velY,velZ
    char line[256];
    FormatEx(line, sizeof(line),
             "%d:%.3f:%.3f:%.1f:%.3f,%.3f,%.3f:%.3f,%.3f,%.3f",
             buttons,
             eye[0], eye[1], 0.0,
             pos[0], pos[1], pos[2],
             vel[0], vel[1], vel[2]);

    WriteFileLine(g_hFile[client], "%s", line);

    return Plugin_Continue;
}

// ====== Helpers ======
bool IsValidLiveClient(int client)
{
    return (1 <= client <= MaxClients) && IsClientInGame(client) && IsPlayerAlive(client);
}
