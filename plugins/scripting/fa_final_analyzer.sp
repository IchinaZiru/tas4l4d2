/**
 *  Finale Analyzer
 *  ---------------------------------------------------------
 *  - finale開始を自動検知して、その場からCI/Tankのスポーンを収集/可視化/保存
 *  - 波(PANIC/PAUSE/TANK/DELAY)を自動セグメントして時刻・長さ・数を集計
 *  - 結果を ems/final_stage/<map>_dump.txt に自動追記
 *  - 簡易メニュー: sm_fa / チャット !fa
 *
 *  Author: Ichinaziru
 *  Version: 1.0.1
 */

#pragma semicolon 1
#pragma newdecls required

#include <sourcemod>
#include <sdktools>
#include <sdkhooks>

#define PL_NAME        "Finale Analyzer"
#define PL_VER         "1.0.1"

// ========= ConVars =========
ConVar g_cvEnable;
ConVar g_cvDraw;
ConVar g_cvDrawLife;
ConVar g_cvMinPanicRate;
ConVar g_cvPauseGap;

// ========= 状態フラグ/カウンタ =========
bool   g_bFinaleActive = false;
bool   g_bTankAlive     = false;

int    g_iWaveIndex     = 0;     // 1,2,3...
enum WaveKind { WAVE_DELAY=0, WAVE_PANIC=1, WAVE_TANK=2, WAVE_PAUSE=3 };
WaveKind g_eCurrentWave = WAVE_DELAY;

float  g_fFinaleStartGT = 0.0;   // GetGameTime() の起点
float  g_fWaveStartGT   = 0.0;

// 直近のCIスポーン記録（レート判定に使う）
int    g_iSpawnInLastBucket = 0;
float  g_fBucketStartGT     = 0.0;

// ====== 集計用 ======
int    g_iWaveCISpawns      = 0;
int    g_iTotalCISpawns     = 0;

int    g_iTankCount         = 0;

// ====== 重複座標のゆるい判定（スナップ） ======
#define SNAP 64.0
ArrayList g_A_SeenPoints;  // float[3]

// ====== ファイルパス ======
char g_sDumpPath[PLATFORM_MAX_PATH];

// ====== メニュー ======
bool g_bMenuOpen[MAXPLAYERS + 1];

// ------------------------------------------------------------

public Plugin myinfo =
{
    name        = PL_NAME,
    author      = "Ichinaziru",
    description = "Auto-logs/visualises CI & Tank spawns in finales and writes a dump file.",
    version     = PL_VER,
    url         = "https://github.com/IchinaZiru/tas4l4d"
};

public void OnPluginStart()
{
    g_cvEnable       = CreateConVar("fa_enable", "1", "Enable Finale Analyzer (1/0).", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvDraw         = CreateConVar("fa_draw", "1", "Draw 3D debug markers (1/0).", FCVAR_NOTIFY, true, 0.0, true, 1.0);
    g_cvDrawLife     = CreateConVar("fa_draw_time", "15.0", "Lifetime of debug markers (seconds).", FCVAR_NOTIFY, true, 1.0, true, 60.0);
    g_cvMinPanicRate = CreateConVar("fa_panic_rate", "1.5", "CI spawns/sec threshold to treat as PANIC.", FCVAR_NOTIFY, true, 0.5, true, 10.0);
    g_cvPauseGap     = CreateConVar("fa_pause_gap", "4.0", "No-spawn seconds to treat as PAUSE.", FCVAR_NOTIFY, true, 1.0, true, 20.0);

    RegConsoleCmd("sm_fa", Cmd_Menu);
    RegConsoleCmd("fa_menu", Cmd_Menu);
    RegConsoleCmd("fa_dump_now", Cmd_DumpNow);

    HookEvent("finale_start",      Event_FinaleStart, EventHookMode_PostNoCopy);
    HookEvent("finale_win",        Event_FinaleEnd,   EventHookMode_PostNoCopy);
    HookEvent("mission_lost",      Event_FinaleEnd,   EventHookMode_PostNoCopy);
    HookEvent("finale_vehicle_leaving", Event_FinaleEnd, EventHookMode_PostNoCopy);

    HookEvent("tank_spawn",  Event_TankSpawn,  EventHookMode_PostNoCopy);
    HookEvent("tank_killed", Event_TankKilled, EventHookMode_PostNoCopy);

    // 念のため trigger_finale の I/O も拾う
    HookEntityOutput("trigger_finale", "FinaleStart", EO_FinaleStart);
    HookEntityOutput("trigger_finale", "FinaleEscapeStart", EO_FinaleEnd);

    g_A_SeenPoints = new ArrayList(3);

    // マップ切り替えで後始末&準備
    HookEvent("round_start", Event_RoundStart, EventHookMode_PostNoCopy);
    HookEvent("round_end",   Event_RoundEnd,   EventHookMode_PostNoCopy);

    PrintToServer("[%s] v%s loaded.", PL_NAME, PL_VER);
}

public void OnMapStart()
{
    BuildDumpPath();
}

public void OnMapEnd()
{
    StopFinaleWatch(false);
}

public void Event_RoundStart(Event e, const char[] name, bool nb)
{
    BuildDumpPath();
    StopFinaleWatch(false);
}

public void Event_RoundEnd(Event e, const char[] name, bool nb)
{
    StopFinaleWatch(false);
}

// ------------------------------------------------------------
// Finale 検知
// ------------------------------------------------------------
public void Event_FinaleStart(Event e, const char[] name, bool dontBroadcast)
{
    StartFinaleWatch("event:finale_start");
}
public void EO_FinaleStart(const char[] output, int caller, int activator, float delay)
{
    StartFinaleWatch("io:FinaleStart");
}
public void Event_FinaleEnd(Event e, const char[] name, bool dontBroadcast)
{
    StopFinaleWatch(true);
}
public void EO_FinaleEnd(const char[] output, int caller, int activator, float delay)
{
    StopFinaleWatch(true);
}

void StartFinaleWatch(const char[] how)
{
    if (!g_cvEnable.BoolValue) return;
    if (g_bFinaleActive) return;

    g_bFinaleActive   = true;
    g_bTankAlive      = false;
    g_eCurrentWave    = WAVE_DELAY;
    g_iWaveIndex      = 1;
    g_fFinaleStartGT  = GetGameTime();
    g_fWaveStartGT    = g_fFinaleStartGT;
    g_fBucketStartGT  = g_fFinaleStartGT;
    g_iSpawnInLastBucket = 0;
    g_iWaveCISpawns   = 0;
    g_iTotalCISpawns  = 0;
    g_iTankCount      = 0;
    g_A_SeenPoints.Clear();

    char map[64]; GetMapNameEx(map, sizeof map);
    PrintToServer("[FA] Finale watch started (%s).", how);
    LogToDump("\n==== Finale START (%s) map=%s time=%.3f ====\n", how, map, g_fFinaleStartGT);

    // 監視タイマー（0.5sごとにレートで波種別を推定）
    CreateTimer(0.5, TMR_Segment, _, TIMER_REPEAT|TIMER_FLAG_NO_MAPCHANGE);
}

void StopFinaleWatch(bool finalEnded)
{
    if (!g_bFinaleActive) return;

    // 最後の波を閉じる
    CloseWave();

    PrintToServer("[FA] Finale watch stopped (%s).", finalEnded ? "finale_end" : "round_end/map_end");
    LogToDump("==== Finale STOP (%s) time=%.3f ====\n", finalEnded ? "finale_end" : "round/map end", GetGameTime());
    g_bFinaleActive = false;
    g_bTankAlive    = false;
}

// ------------------------------------------------------------
// タイマー：CIレートから波種別(PANIC/PAUSE)を推定
// ------------------------------------------------------------
public Action TMR_Segment(Handle timer, any data)
{
    if (!g_bFinaleActive) return Plugin_Stop;

    float now = GetGameTime();

    // 直近0.5s ぶんは g_iSpawnInLastBucket に積んである
    float elapsed = now - g_fBucketStartGT;
    float rate = (elapsed > 0.0) ? (float(g_iSpawnInLastBucket) / elapsed) : 0.0;

    // Tank区間は別扱い
    if (!g_bTankAlive)
    {
        if (rate >= g_cvMinPanicRate.FloatValue)
        {
            if (g_eCurrentWave != WAVE_PANIC)
                SwitchWave(WAVE_PANIC, "rate>=panic");
        }
        else
        {
            static float s_fNoSpawnStart = 0.0;
            if (g_iSpawnInLastBucket == 0)
            {
                if (s_fNoSpawnStart <= 0.0) s_fNoSpawnStart = now;
                if (now - s_fNoSpawnStart >= g_cvPauseGap.FloatValue && g_eCurrentWave != WAVE_PAUSE)
                    SwitchWave(WAVE_PAUSE, "no-spawn gap");
            }
            else
            {
                s_fNoSpawnStart = 0.0;
                if (g_eCurrentWave != WAVE_DELAY && g_eCurrentWave != WAVE_PANIC)
                    SwitchWave(WAVE_DELAY, "low-rate");
            }
        }
    }

    // バケット更新
    g_fBucketStartGT = now;
    g_iSpawnInLastBucket = 0;

    return Plugin_Continue;
}

// ------------------------------------------------------------
// Tank
// ------------------------------------------------------------
public void Event_TankSpawn(Event e, const char[] name, bool nb)
{
    if (!g_bFinaleActive) return;
    g_bTankAlive = true;
    g_iTankCount++;

    int tank = -1;
    int userid = e.GetInt("userid");
    if (userid) tank = GetClientOfUserId(userid);

    float pos[3];
    if (tank > 0 && IsClientInGame(tank))
        GetClientAbsOrigin(tank, pos);
    else
        GetEntOriginSafe(FindEntityByClassname(-1, "tank"), pos); // フォールバック

    char t[64]; GetClock(t, sizeof t);
    PrintToServer("[FA] TANK #%d SPAWN @ (%.1f %.1f %.1f) [%s]", g_iTankCount, pos[0],pos[1],pos[2], t);
    LogToDump("TANK_SPAWN #%d %.1f %.1f %.1f time=%.3f\n", g_iTankCount, pos[0],pos[1],pos[2], GetGameTime());
    DrawMarker(pos, 255, 64, 64, "TANK");
    SwitchWave(WAVE_TANK, "tank_spawn");
}

public void Event_TankKilled(Event e, const char[] name, bool nb)
{
    if (!g_bFinaleActive) return;

    g_bTankAlive = false;
    char t[64]; GetClock(t, sizeof t);
    PrintToServer("[FA] TANK DOWN [%s]", t);
    LogToDump("TANK_KILLED time=%.3f\n", GetGameTime());

    SwitchWave(WAVE_DELAY, "tank_killed");
}

// ------------------------------------------------------------
// エンティティ生成監視：CIスポーン拾い
// ------------------------------------------------------------
public void OnEntityCreated(int entity, const char[] classname)
{
    if (!g_bFinaleActive) return;
    if (StrEqual(classname, "infected"))
    {
        SDKHook(entity, SDKHook_SpawnPost, OnCISpawned);
    }
}

public void OnCISpawned(int ent)
{
    if (!IsValidEntity(ent) || !g_bFinaleActive) return;

    float pos[3]; GetEntOriginSafe(ent, pos);

    // 直近バケットへ加算
    g_iSpawnInLastBucket++;
    g_iWaveCISpawns++;
    g_iTotalCISpawns++;

    char t[64]; GetClock(t, sizeof t);

    char wname[8]; WaveToStr(g_eCurrentWave, wname, sizeof wname);
    PrintToServer("[FA] CI @ (%.1f %.1f %.1f) wave=%d kind=%s [%s]",
        pos[0],pos[1],pos[2], g_iWaveIndex, wname, t);

    LogToDump("CI %.1f %.1f %.1f wave=%d kind=%s time=%.3f\n",
        pos[0],pos[1],pos[2], g_iWaveIndex, wname, GetGameTime());

    // 既知ポイントへの登録と可視化（近傍重複は省く）
    if (RegisterPointIfNew(pos))
    {
        if (g_cvDraw.BoolValue)
        {
            DrawMarker(pos, 80, 200, 80, "CI");
        }
    }
}

// ------------------------------------------------------------
// 波の切替とクローズ
// ------------------------------------------------------------
void SwitchWave(WaveKind next, const char[] why)
{
    if (!g_bFinaleActive) return;
    if (g_eCurrentWave == next) return;

    // 現在の波を閉じて、次へ
    CloseWave();

    g_eCurrentWave = next;
    g_iWaveIndex++;
    g_fWaveStartGT = GetGameTime();

    char wname[8]; WaveToStr(next, wname, sizeof wname);
    PrintToServer("[FA] >>> Wave %d START kind=%s (%s)", g_iWaveIndex, wname, why);
    LogToDump("WAVE_START %d %s time=%.3f reason=%s\n", g_iWaveIndex, wname, g_fWaveStartGT, why);

    g_iWaveCISpawns = 0;
}

void CloseWave()
{
    if (g_fWaveStartGT <= 0.0) return;

    float now = GetGameTime();
    float dur = now - g_fWaveStartGT;

    if (g_iWaveIndex > 0)
    {
        char wname[8]; WaveToStr(g_eCurrentWave, wname, sizeof wname);
        PrintToServer("[FA] <<< Wave %d END kind=%s  dur=%.2fs  ci=%d",
            g_iWaveIndex, wname, dur, g_iWaveCISpawns);

        LogToDump("WAVE_END %d %s dur=%.3f ci=%d time=%.3f\n",
            g_iWaveIndex, wname, dur, g_iWaveCISpawns, now);
    }
}

// 文字列は戻り値NG → 出力バッファ方式
stock void WaveToStr(WaveKind k, char[] out, int maxlen)
{
    switch (k)
    {
        case WAVE_PANIC: strcopy(out, maxlen, "PANIC");
        case WAVE_TANK:  strcopy(out, maxlen, "TANK");
        case WAVE_PAUSE: strcopy(out, maxlen, "PAUSE");
        default:         strcopy(out, maxlen, "DELAY");
    }
}

// ------------------------------------------------------------
// 可視化（VScript DebugDraw* を RunScriptCode で呼ぶ）
// ------------------------------------------------------------
void DrawMarker(const float pos[3], int r, int g, int b, const char[] label)
{
    if (!g_cvDraw.BoolValue) return;

    float life = g_cvDrawLife.FloatValue;

    // 円
    char code[256];
    Format(code, sizeof code,
        "DebugDrawCircle(Vector(%.1f, %.1f, %.1f), 40, %d, %d, %d, false, %.1f)",
        pos[0], pos[1], pos[2], r, g, b, life);
    SetVariantString(code);
    AcceptEntityInput(0, "RunScriptCode");

    // テキスト
    Format(code, sizeof code,
        "DebugDrawText(Vector(%.1f, %.1f, %.1f), \"%s\", false, %.1f)",
        pos[0], pos[1], pos[2] + 36.0, label, life);
    SetVariantString(code);
    AcceptEntityInput(0, "RunScriptCode");
}

// ------------------------------------------------------------
// 既知座標の登録（近傍重複をはじく）
// ------------------------------------------------------------
bool RegisterPointIfNew(const float pos[3])
{
    float p[3];
    for (int i = 0; i < g_A_SeenPoints.Length; i++)
    {
        g_A_SeenPoints.GetArray(i, p, 3);
        if (FloatAbs(p[0]-pos[0]) < SNAP &&
            FloatAbs(p[1]-pos[1]) < SNAP &&
            FloatAbs(p[2]-pos[2]) < SNAP)
        {
            return false;
        }
    }
    g_A_SeenPoints.PushArray(pos, 3);
    return true;
}

// ------------------------------------------------------------
// ダンプ関連
// ------------------------------------------------------------
void BuildDumpPath()
{
    // 相対パスはゲームディレクトリ基準（left4dead2/）
    if (!DirExists("ems"))
        CreateDirectory("ems", 511, false);

    if (!DirExists("ems/final_stage"))
        CreateDirectory("ems/final_stage", 511, false);

    char map[64];
    GetMapNameEx(map, sizeof map);

    // 例: left4dead2/ems/final_stage/c2m5_concert_dump.txt
    Format(g_sDumpPath, sizeof g_sDumpPath, "ems/final_stage/%s_dump.txt", map);
}

void LogToDump(const char[] fmt, any ...)
{
    static char buffer[1024];
    VFormat(buffer, sizeof buffer, fmt, 2);

    File f = OpenFile(g_sDumpPath, "a");
    if (f != null)
    {
        f.WriteString(buffer, false);
        delete f;
    }
}

public Action Cmd_DumpNow(int client, int args)
{
    if (!g_bFinaleActive)
    {
        ReplyToCommand(client, "[FA] Finale is not active.");
        return Plugin_Handled;
    }

    // 波をいったん閉じて現状を吐く（継続するために即再開）
    WaveKind cur = g_eCurrentWave;
    int     idx = g_iWaveIndex;

    CloseWave();
    LogToDump("DUMP_NOW total_ci=%d tanks=%d seen_pts=%d time=%.3f\n",
        g_iTotalCISpawns, g_iTankCount, g_A_SeenPoints.Length, GetGameTime());

    char map[64]; GetMapNameEx(map, sizeof map);
    PrintToChatAll("\x04[FA]\x01 Dumped to: ems/final_stage/%s_dump.txt", map);

    // 再開
    g_eCurrentWave  = cur;
    g_iWaveIndex    = idx;
    g_fWaveStartGT  = GetGameTime();

    return Plugin_Handled;
}

// ------------------------------------------------------------
// メニュー
// ------------------------------------------------------------
public Action Cmd_Menu(int client, int args)
{
    if (client <= 0 || !IsClientInGame(client)) client = 1;

    Panel p = new Panel();
    p.SetTitle("Finale Analyzer\n ");

    char line[128], map[64]; GetMapNameEx(map, sizeof map);

    Format(line, sizeof line, "Monitoring: %s", g_bFinaleActive ? "ON" : "OFF");
    p.DrawText(line);

    Format(line, sizeof line, "Dump file: ems/final_stage/%s_dump.txt", map);
    p.DrawText(line);

    p.DrawText(" ");

    p.DrawItem(g_bFinaleActive ? "Stop Monitoring" : "Start Monitoring");
    p.DrawItem(g_cvDraw.BoolValue ? "Draw: ON" : "Draw: OFF");
    p.DrawItem("Dump Now");
    p.DrawItem("Clear Markers");
    p.DrawItem("Exit");

    g_bMenuOpen[client] = true;
    p.Send(client, MenuH, 45);
    delete p;
    return Plugin_Handled;
}

public int MenuH(Menu menu, MenuAction action, int client, int item)
{
    if (action == MenuAction_End) { delete menu; return 0; }
    if (action != MenuAction_Select) return 0;

    switch (item)
    {
        case 1:
        {
            if (g_bFinaleActive) StopFinaleWatch(false);
            else StartFinaleWatch("manual");
            ClientCommand(client, "playgamesound buttons/blip1.wav");
        }
        case 2:
        {
            g_cvDraw.SetBool(!g_cvDraw.BoolValue);
            ClientCommand(client, "playgamesound buttons/blip1.wav");
        }
        case 3:
        {
            Cmd_DumpNow(client, 0);
        }
        case 4:
        {
            SetVariantString("DebugDrawClear()");
            AcceptEntityInput(0, "RunScriptCode");
            ClientCommand(client, "playgamesound Buttons.snd10");
        }
        default:
        {
            g_bMenuOpen[client] = false;
            ClientCommand(client, "playgamesound buttons/button11.wav");
            return 0;
        }
    }

    if (g_bMenuOpen[client]) Cmd_Menu(client, 0);
    return 0;
}

// ------------------------------------------------------------
// ユーティリティ
// ------------------------------------------------------------
void GetClock(char[] out, int size)
{
    FormatTime(out, size, "%H:%M:%S");
}

// こちらも戻り値ではなくバッファ渡し
stock void GetMapNameEx(char[] map, int maxlen)
{
    GetCurrentMap(map, maxlen);
}

bool GetEntOriginSafe(int ent, float pos[3])
{
    if (IsValidEntity(ent))
    {
        GetEntPropVector(ent, Prop_Send, "m_vecOrigin", pos);
        return true;
    }
    pos[0]=pos[1]=pos[2]=0.0;
    return false;
}
