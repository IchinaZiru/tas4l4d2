/*************************************************
 * l4d2_transit_tools.sp  (rev.1: save path patched)
 *  - Map-to-map coordinate transit helper
 *  - Forward / Reverse mapping, teleport option
 *  - Debug beams (pre / aft / delta / mapping)
 *
 * Commands:
 *   !tpre                : save P1 (pre) on current map
 *   !taft [nextmap]      : save P2 (aft) -> compute & save delta
 *   !transit             : show forward mapped point (P+Δ) + beams
 *   !transit_tp          : teleport to P+Δ
 *   !rtransit [prevmap]  : show reverse mapped point (P-Δ) + beams
 *   !rtransit_tp [prev]  : teleport to P-Δ
 *   !tvis                : visualize pre/aft/Δ and P->mapped beams
 *
 * Data file (auto-created/updated):
 *   cfg/sm_server/sourcemod/data/l4d2_transit_pairs.cfg
 **************************************************/

#include <sourcemod>
#include <sdktools>
#include <sdktools_tempents>
#include <halflife>    // PrintCenterTextAll()

#pragma semicolon 1
#pragma newdecls required

// Storage path adjusted for your server layout
#define PAIRS_FILE_REL "cfg/sm_server/sourcemod/data/l4d2_transit_pairs.cfg"
#define BEAM_MATERIAL  "materials/sprites/laserbeam.vmt"
#define GLOW_MATERIAL  "materials/sprites/glow01.vmt"

ConVar gCvarBeamTime, gCvarBeamWidth, gCvarBeamHeight;
int    g_iBeamModel = -1, g_iGlowModel = -1;

char   g_sPairsPath[PLATFORM_MAX_PATH];    // absolute path
char   g_sLastPreMap[64];
float  g_vLastPre[3];
bool   g_bHasLastPre = false;

public Plugin myinfo =
{
    name        = "L4D2 Transit Tools",
    author      = "IchinaZiru",
    description = "Map coordinate transit (forward/reverse) with visualization and optional teleport",
    version     = "1.0.1 Beta",
    url         = "https://github.com/IchinaZiru/tas4l4d2"
};

/*** ---------- lifecycle ---------- ***/
public void OnPluginStart()
{
    // Use Path_Game here (points to cfg/... folder)
    BuildPath(Path_SM, g_sPairsPath, sizeof g_sPairsPath, "../../%s", PAIRS_FILE_REL);

    RegConsoleCmd("sm_tpre", CmdPre);
    RegConsoleCmd("sm_taft", CmdAft);
    RegConsoleCmd("sm_transit", CmdTransit);
    RegConsoleCmd("sm_transit_tp", CmdTransitTP);
    RegConsoleCmd("sm_rtransit", CmdRTransit);
    RegConsoleCmd("sm_rtransit_tp", CmdRTransitTP);
    RegConsoleCmd("sm_tvis", CmdVisualize);

    gCvarBeamTime   = CreateConVar("l4d2_transit_beam_time", "6.0", "Beam life time (sec)");
    gCvarBeamWidth  = CreateConVar("l4d2_transit_beam_width", "4.0", "Beam width (units)");
    gCvarBeamHeight = CreateConVar("l4d2_transit_beam_height", "160.0", "Beacon vertical height");

    AutoExecConfig(true, "l4d2_transit_tools");

    PrintToServer("[TransitTools] loaded. Data: %s", g_sPairsPath);
}

public void OnMapStart()
{
    g_iBeamModel  = PrecacheModel(BEAM_MATERIAL, true);
    g_iGlowModel  = PrecacheModel(GLOW_MATERIAL, true);

    g_bHasLastPre = false;
    GetCurrentMap(g_sLastPreMap, sizeof(g_sLastPreMap));
}

/*** ---------- commands ---------- ***/
public Action CmdPre(int client, int args)
{
    if (!IsClientValidAlive(client)) return Plugin_Handled;

    GetClientAbsOrigin(client, g_vLastPre);
    GetCurrentMap(g_sLastPreMap, sizeof g_sLastPreMap);
    g_bHasLastPre = true;

    PrintToChat(client, "\x05[Transit]\x01 P1(pre) 記録: (%.2f, %.2f, %.2f) on \x03%s",
                g_vLastPre[0], g_vLastPre[1], g_vLastPre[2], g_sLastPreMap);

    int blue[4] = { 80, 160, 255, 255 };
    DrawBeacon(g_vLastPre, blue);
    return Plugin_Handled;
}

public Action CmdAft(int client, int args)
{
    if (!IsClientValidAlive(client)) return Plugin_Handled;
    if (!g_bHasLastPre)
    {
        PrintToChat(client, "\x05[Transit]\x01 先に \x03!tpre\x01 で P1(pre) を記録してください。");
        return Plugin_Handled;
    }

    char curMap[64];
    GetCurrentMap(curMap, sizeof curMap);

    char nextMap[64];
    if (args >= 1)
    {
        GetCmdArg(1, nextMap, sizeof nextMap);
    }
    else
    {
        if (!FindNextMapName(nextMap, sizeof nextMap))
            strcopy(nextMap, sizeof nextMap, curMap);    // fallback
    }

    float vAft[3];
    GetClientAbsOrigin(client, vAft);

    float delta[3];
    delta[0] = vAft[0] - g_vLastPre[0];
    delta[1] = vAft[1] - g_vLastPre[1];
    delta[2] = vAft[2] - g_vLastPre[2];

    SavePair(g_sLastPreMap, nextMap, g_vLastPre, vAft, delta);

    PrintToChatAll("\x05[Transit]\x01 Δ 保存: \x03%s\x01 -> \x04%s\x01  Δ=(%.2f, %.2f, %.2f)",
                   g_sLastPreMap, nextMap, delta[0], delta[1], delta[2]);

    int purple[4] = { 200, 100, 255, 255 };
    int yellow[4] = { 255, 220, 80, 255 };
    int green[4]  = { 60, 220, 120, 255 };
    DrawBeacon(g_vLastPre, purple);
    DrawBeacon(vAft, yellow);
    DrawArrow(g_vLastPre, vAft, green);

    return Plugin_Handled;
}

public Action CmdTransit(int client, int args)
{
    if (!IsClientValidAlive(client)) return Plugin_Handled;

    char curMap[64];
    GetCurrentMap(curMap, sizeof curMap);
    char nextMap[64];
    if (args >= 1) GetCmdArg(1, nextMap, sizeof nextMap);
    else FindNextMapName(nextMap, sizeof nextMap);

    float delta[3];
    if (!LoadDelta(curMap, nextMap, delta))
    {
        PrintToChat(client, "\x05[Transit]\x01 Δ 未登録: %s -> %s  （!tpre→!taftで作成）", curMap, nextMap[0] ? nextMap : "(unknown)");
        return Plugin_Handled;
    }

    float p[3];
    GetClientAbsOrigin(client, p);
    float mapped[3];
    mapped[0] = p[0] + delta[0];
    mapped[1] = p[1] + delta[1];
    mapped[2] = p[2] + delta[2];

    PrintToChat(client, "\x05[Transit]\x01 %s → %s  P=(%.2f,%.2f,%.2f)  P+Δ=(%.2f,%.2f,%.2f)",
                curMap, nextMap[0] ? nextMap : "(unknown)", p[0], p[1], p[2], mapped[0], mapped[1], mapped[2]);

    VisualizeAll(curMap, nextMap, p, mapped, delta, false);
    return Plugin_Handled;
}

public Action CmdTransitTP(int client, int args)
{
    if (!IsClientValidAlive(client)) return Plugin_Handled;

    char curMap[64];
    GetCurrentMap(curMap, sizeof curMap);
    char nextMap[64];
    if (args >= 1) GetCmdArg(1, nextMap, sizeof nextMap);
    else FindNextMapName(nextMap, sizeof nextMap);

    float delta[3];
    if (!LoadDelta(curMap, nextMap, delta))
    {
        PrintToChat(client, "\x05[Transit]\x01 Δ 未登録: %s -> %s", curMap, nextMap[0] ? nextMap : "(unknown)");
        return Plugin_Handled;
    }

    float p[3];
    GetClientAbsOrigin(client, p);
    p[0] += delta[0];
    p[1] += delta[1];
    p[2] += delta[2];
    TeleportEntity(client, p, NULL_VECTOR, NULL_VECTOR);

    PrintToChat(client, "\x05[Transit]\x01 テレポート: P ← P+Δ  (Δ=%.2f,%.2f,%.2f)", delta[0], delta[1], delta[2]);
    return Plugin_Handled;
}

public Action CmdRTransit(int client, int args)
{
    if (!IsClientValidAlive(client)) return Plugin_Handled;

    char curMap[64];
    GetCurrentMap(curMap, sizeof curMap);
    char prevMap[64] = "";

    if (args >= 1) GetCmdArg(1, prevMap, sizeof prevMap);
    else FindPrevMapFor(curMap, prevMap, sizeof prevMap);

    if (!prevMap[0])
    {
        PrintToChat(client, "\x05[Transit]\x01 逆写像の前マップが特定できません。引数で前マップ名を指定してください。");
        return Plugin_Handled;
    }

    float delta[3];
    if (!LoadDelta(prevMap, curMap, delta))
    {
        PrintToChat(client, "\x05[Transit]\x01 Δ 未登録: %s -> %s", prevMap, curMap);
        return Plugin_Handled;
    }

    float p[3];
    GetClientAbsOrigin(client, p);
    float mapped[3];
    mapped[0] = p[0] - delta[0];
    mapped[1] = p[1] - delta[1];
    mapped[2] = p[2] - delta[2];

    PrintToChat(client, "\x05[Transit]\x01 %s ← %s  P=(%.2f,%.2f,%.2f)  P-Δ=(%.2f,%.2f,%.2f)",
                prevMap, curMap, p[0], p[1], p[2], mapped[0], mapped[1], mapped[2]);

    float neg[3];
    neg[0] = -delta[0];
    neg[1] = -delta[1];
    neg[2] = -delta[2];
    VisualizeAll(prevMap, curMap, p, mapped, neg, true);
    return Plugin_Handled;
}

public Action CmdRTransitTP(int client, int args)
{
    if (!IsClientValidAlive(client)) return Plugin_Handled;

    char curMap[64];
    GetCurrentMap(curMap, sizeof curMap);
    char prevMap[64] = "";
    if (args >= 1) GetCmdArg(1, prevMap, sizeof prevMap);
    else FindPrevMapFor(curMap, prevMap, sizeof prevMap);

    if (!prevMap[0])
    {
        PrintToChat(client, "\x05[Transit]\x01 逆写像の前マップが特定できません。引数で前マップ名を指定してください。");
        return Plugin_Handled;
    }

    float delta[3];
    if (!LoadDelta(prevMap, curMap, delta))
    {
        PrintToChat(client, "\x05[Transit]\x01 Δ 未登録: %s -> %s", prevMap, curMap);
        return Plugin_Handled;
    }

    float p[3];
    GetClientAbsOrigin(client, p);
    p[0] -= delta[0];
    p[1] -= delta[1];
    p[2] -= delta[2];
    TeleportEntity(client, p, NULL_VECTOR, NULL_VECTOR);

    PrintToChat(client, "\x05[Transit]\x01 テレポート: P ← P-Δ  (Δ=%.2f,%.2f,%.2f)", delta[0], delta[1], delta[2]);
    return Plugin_Handled;
}

public Action CmdVisualize(int client, int args)
{
    if (!IsClientValidAlive(client)) return Plugin_Handled;

    char curMap[64];
    GetCurrentMap(curMap, sizeof curMap);
    char nextMap[64];
    if (!FindNextMapName(nextMap, sizeof nextMap)) nextMap[0] = '\0';

    float delta[3], pre[3], aft[3];
    bool  has = LoadPair(curMap, nextMap, pre, aft, delta);

    if (has)
    {
        int purple[4] = { 200, 100, 255, 255 };
        int yellow[4] = { 255, 220, 80, 255 };
        int green[4]  = { 60, 220, 120, 255 };
        DrawBeacon(pre, purple);
        DrawBeacon(aft, yellow);
        DrawArrow(pre, aft, green);

        float p[3];
        GetClientAbsOrigin(client, p);
        float mapped[3];
        mapped[0] = p[0] + delta[0];
        mapped[1] = p[1] + delta[1];
        mapped[2] = p[2] + delta[2];
        VisualizeAll(curMap, nextMap[0] ? nextMap : "(unknown)", p, mapped, delta, false);

        PrintToChat(client, "\x05[Transit]\x01 可視化: pre / aft / Δ を表示しました。");
    }
    else
    {
        PrintToChat(client, "\x05[Transit]\x01 Δ 情報が見つかりません。!tpre → （遷移） → !taft を先に実行してください。");
    }
    return Plugin_Handled;
}

/*** ---------- helpers ---------- ***/

bool IsClientValidAlive(int client)
{
    return (client > 0 && client <= MaxClients && IsClientInGame(client) && IsPlayerAlive(client));
}

bool FindNextMapName(char[] name, int maxlen)
{
    int ent = -1;
    while ((ent = FindEntityByClassname(ent, "info_changelevel")) != -1)
    {
        GetEntPropString(ent, Prop_Data, "m_mapName", name, maxlen);
        if (name[0]) return true;
    }
    name[0] = '\0';
    return false;
}

void SavePair(const char[] preMap, const char[] nextMap, const float pre[3], const float aft[3], const float delta[3])
{
    KeyValues kv = new KeyValues("TransitPairs");
    if (FileExists(g_sPairsPath)) kv.ImportFromFile(g_sPairsPath);

    kv.JumpToKey(preMap, true);
    kv.JumpToKey(nextMap, true);

    char buf[128];
    Format(buf, sizeof buf, "%.6f %.6f %.6f", pre[0], pre[1], pre[2]);
    kv.SetString("pre", buf);
    Format(buf, sizeof buf, "%.6f %.6f %.6f", aft[0], aft[1], aft[2]);
    kv.SetString("aft", buf);
    Format(buf, sizeof buf, "%.6f %.6f %.6f", delta[0], delta[1], delta[2]);
    kv.SetString("delta", buf);

    kv.Rewind();
    kv.ExportToFile(g_sPairsPath);
    delete kv;
}

bool LoadDelta(const char[] preMap, const char[] nextMap, float delta[3])
{
    float pre[3], aft[3];
    return LoadPair(preMap, nextMap, pre, aft, delta);
}

bool LoadPair(const char[] preMap, const char[] nextMap, float pre[3], float aft[3], float delta[3])
{
    KeyValues kv = new KeyValues("TransitPairs");
    if (!kv.ImportFromFile(g_sPairsPath))
    {
        delete kv;
        return false;
    }

    bool ok = false;

    if (kv.JumpToKey(preMap, false))
    {
        if (nextMap[0] && kv.JumpToKey(nextMap, false))
        {
            ok = ReadVecsFromKv(kv, pre, aft, delta);
        }
        else
        {
            if (kv.GotoFirstSubKey(false))
            {
                ok = ReadVecsFromKv(kv, pre, aft, delta);
            }
        }
    }

    delete kv;
    return ok;
}

bool ReadVecsFromKv(KeyValues kv, float pre[3], float aft[3], float delta[3])
{
    char s[128];
    if (!kv.GetString("delta", s, sizeof s)) return false;    // Δ required
    StrToVec(s, delta);

    if (kv.GetString("pre", s, sizeof s)) StrToVec(s, pre);
    if (kv.GetString("aft", s, sizeof s)) StrToVec(s, aft);
    return true;
}

void StrToVec(const char[] s, float v[3])
{
    char a[3][32];
    int  n = ExplodeString(s, " ", a, 3, 32);
    if (n >= 3)
    {
        v[0] = StringToFloat(a[0]);
        v[1] = StringToFloat(a[1]);
        v[2] = StringToFloat(a[2]);
    }
}

void FindPrevMapFor(const char[] curMap, char[] prevMap, int maxlen)
{
    prevMap[0]   = '\0';

    KeyValues kv = new KeyValues("TransitPairs");
    if (!kv.ImportFromFile(g_sPairsPath))
    {
        delete kv;
        return;
    }

    if (kv.GotoFirstSubKey(false))
    {
        do
        {
            char pre[64];
            kv.GetSectionName(pre, sizeof pre);
            if (kv.GotoFirstSubKey(false))
            {
                do
                {
                    char nxt[64];
                    kv.GetSectionName(nxt, sizeof nxt);
                    if (StrEqual(nxt, curMap))
                    {
                        strcopy(prevMap, maxlen, pre);
                        kv.Rewind();
                        delete kv;
                        return;
                    }
                }
                while (kv.GotoNextKey(false));
                kv.GoBack();
            }
        }
        while (kv.GotoNextKey(false));
    }
    kv.Rewind();
    delete kv;
}

/*** ---------- visualization ---------- ***/

void VisualizeAll(const char[] fromMap, const char[] toMap, const float p[3], const float mapped[3], const float delta[3], bool reverse)
{
    int cyan[4]   = { 80, 200, 255, 255 };    // current P
    int orange[4] = { 255, 160, 60, 255 };    // mapped
    int green[4]  = { 60, 220, 120, 255 };    // forward arrow
    int red[4]    = { 255, 80, 80, 255 };     // reverse arrow

    DrawBeacon(p, cyan);
    DrawBeacon(mapped, orange);
    DrawArrow(p, mapped, reverse ? red : green);

    PrintCenterTextAll("%s → %s\nΔ = (%.2f, %.2f, %.2f)\nP %s Δ",
                       fromMap, toMap[0] ? toMap : "(unknown)", delta[0], delta[1], delta[2], reverse ? "−" : "＋");
}

void DrawBeacon(const float pos[3], const int color[4])
{
    float top[3];
    top[0] = pos[0];
    top[1] = pos[1];
    top[2] = pos[2] + GetConVarFloat(gCvarBeamHeight);

    TE_SetupBeamPoints(pos, top, g_iBeamModel, 0, 0, 0,
                       GetConVarFloat(gCvarBeamTime),
                       GetConVarFloat(gCvarBeamWidth),
                       GetConVarFloat(gCvarBeamWidth), 1, 0.0, color, 0);
    TE_SendToAll();

    TE_SetupGlowSprite(pos, g_iGlowModel, GetConVarFloat(gCvarBeamTime), 1.5, 255);
    TE_SendToAll();
}

void DrawArrow(const float from[3], const float to[3], const int color[4])
{
    TE_SetupBeamPoints(from, to, g_iBeamModel, 0, 0, 0,
                       GetConVarFloat(gCvarBeamTime),
                       GetConVarFloat(gCvarBeamWidth),
                       GetConVarFloat(gCvarBeamWidth), 1, 0.0, color, 0);
    TE_SendToAll();
}
