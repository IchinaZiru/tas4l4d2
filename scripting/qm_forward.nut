// qm_forward.nut
// Forward playback with optional jump, overwrite-safe, no prebuilt frames
// Scripted by Ichina

// -- namespace ---------------------------------------------------------------
if (!("QMF" in getroottable())) ::QMF <- {};

// playback flags (kept in sync for compatibility)
::QMF._playing <- false;
::QMF.isPlaying <- false;
::QMF._setPlaying <- function(b) { this._playing = b; this.isPlaying = b; };

// runtime caches
::QMF._target <- null;
::QMF._targetName <- "!nick";     // default survivor handle
::QMF._lastPos <- null;
::QMF._lastAng <- null;
::QMF._lastVel <- null;

// jump helpers (defaults)
::QMF._defaultLift <- 16.0;       // units to lift before jump
::QMF._defaultZHold <- 2;         // frames to keep Z velocity

// generator state (no frame array)
::QMF._gen <- {
    active = false,   // generator is running
    phase = 0,        // 0=jump lift, 1=jump hold, 2=horizontal
    vx = 0.0, vy = 0.0, vz = 0.0,
    dt = 0.05,
    ticks = 0,        // remaining horizontal frames
    zhold = 0,        // remaining hold frames
    lift = 16.0
};

// -- utils -------------------------------------------------------------------
::QMF._deg2rad <- function(d) { return d * 3.1415926535 / 180.0; };

::QMF._trimSpaces <- function(s) {
    if (typeof s != "string") return s;
    local L = s.len(), i = 0, j = L - 1;
    while (i < L && (s[i] == ' ' || s[i] == '\t')) i++;
    while (j >= i && (s[j] == ' ' || s[j] == '\t')) j--;
    return (i>j) ? "" : s.slice(i, j+1);
};

// entity resolve: Ent("!nick") -> FindByName -> first survivor
::QMF._entByName <- function(name) {
    try { if ("Ent" in getroottable()) { local e = ::Ent(name); if (e && e.IsValid()) return e; } } catch(e) {}
    try { local e = Entities.FindByName(null, name); if (e && e.IsValid()) return e; } catch(e2) {}
    return null;
};
::QMF._anySurvivor <- function() {
    local e = null;
    while ((e = Entities.FindByClassname(e, "player"))) {
        if (!e || !e.IsValid()) continue;
        if (("IsSurvivor" in e)) { try { if (!e.IsSurvivor()) continue; } catch(_) {} }
        return e;
    }
    return null;
};
::QMF._ensureTarget <- function() {
    if (this._target && this._target.IsValid()) return true;
    if (typeof this._targetName == "string" && this._targetName.len() > 0) {
        local e = this._entByName(this._targetName);
        if (e && e.IsValid()) { this._target = e; return true; }
    }
    local aliases = ["!nick","!coach","!ellis","!rochelle","!zoey","!francis","!bill","!louis"];
    foreach (n in aliases) {
        local e = this._entByName(n);
        if (e && e.IsValid()) { this._target = e; this._targetName = n; return true; }
    }
    local any = this._anySurvivor();
    if (any) { this._target = any; this._targetName = "(first survivor)"; return true; }
    return false;
};

// safe setters (with fallbacks)
::QMF._trySetOrigin <- function(ent, pos) {
    try { if (("SetOrigin" in ent)) { ent.SetOrigin(pos); return true; } } catch(e) {}
    try { EntFireByHandle(ent,"AddOutput",format("origin %.3f %.3f %.3f",pos.x,pos.y,pos.z),0.0,null,null); return true; } catch(e2) {}
    return false;
};
::QMF._trySetAngles <- function(ent, ang) {
    try { if (("SnapEyeAngles" in ent)) { ent.SnapEyeAngles(ang); return true; } } catch(e) {}
    try { if (("SetAngles" in ent)) { ent.SetAngles(ang.x, ang.y, ang.z); return true; } } catch(e2) {}
    return false;
};
::QMF._trySetVelocity <- function(ent, vel) {
    try { if (("SetVelocity" in ent)) { ent.SetVelocity(vel); return true; } } catch(e) {}
    try { EntFireByHandle(ent,"AddOutput",format("basevelocity %.3f %.3f %.3f",vel.x,vel.y,vel.z),0.0,null,null); return true; } catch(e2) {}
    return false;
};

::QMF._schedule <- function(delay) {
    DoEntFire("!self", "RunScriptCode", "::QMF._tick()", delay, null, null);
};

// -- public API --------------------------------------------------------------
::QMF.SetTarget <- function(name) {
    if (this._playing) { print("[QMF] stop first\n"); return false; }
    this._targetName = (name.len() && name[0]=='!') ? name.tolower() : ("!" + name.tolower());
    this._target = null;
    local ok = this._ensureTarget();
    print(format("[QMF] target=%s (%s)\n", this._targetName, ok ? "resolved" : "not found"));
    return ok;
};

::QMF.Stop <- function() {
    if (!this._playing) { print("[QMF] stopped\n"); return; }
    this._gen.active = false;
    this._setPlaying(false);
    print("[QMF] stopped\n");
};

// overwrite-safe playback, no prebuilt frames
::QMF.PlayForward <- function(speed = 320.0, dt = 0.05, ticks = 10, up = 0.0, lift = null, zhold = null) {
    if (!this._ensureTarget()) { print("[QMF] no survivor player found (target=" + this._targetName + ")\n"); return false; }

    // overwrite current playback
    this._gen.active = false;
    this._setPlaying(false);

    // resolve params
    local a = this._target.GetAngles();
    local yaw = this._deg2rad(a.y);
    local vx = speed.tofloat() * cos(yaw);
    local vy = speed.tofloat() * sin(yaw);
    local vz = up.tofloat();
    local L  = (lift  == null) ? this._defaultLift  : lift.tofloat();
    local H  = (zhold == null) ? this._defaultZHold : zhold.tointeger();

    // clamp to avoid heavy work
    if (ticks < 0) ticks = 0;
    if (H < 0) H = 0;
    if (dt < 0.0) dt = 0.0;

    // init generator
    this._gen.vx = vx; this._gen.vy = vy; this._gen.vz = vz;
    this._gen.dt = dt.tofloat(); this._gen.ticks = ticks.tointeger();
    this._gen.zhold = (vz > 0.0) ? H : 0;
    this._gen.lift = L;
    this._gen.phase = (vz > 0.0) ? 0 : 2;
    this._gen.active = true;

    // reset caches
    this._lastPos = null; this._lastAng = null; this._lastVel = null;
    this._setPlaying(true);

    print(format("[QMF] PlayForward target=%s speed=%.1f dt=%.3f ticks=%d up=%.1f lift=%.1f zhold=%d\n",
                 this._targetName, speed.tofloat(), dt.tofloat(), ticks.tointeger(),
                 up.tofloat(), L, this._gen.zhold));

    // start immediately
    this._tick();
    return true;
};

// -- tick (generator) --------------------------------------------------------
::QMF._tick <- function() {
    if (!this._playing || !this._gen.active) return;
    if (!this._target || !this._target.IsValid()) { this._gen.active = false; this._setPlaying(false); print("[QMF] finished\n"); return; }

    // Phase 0: jump lift (teleport up slightly + upward velocity)
    if (this._gen.phase == 0) {
        local p0 = this._target.GetOrigin();
        local p1 = Vector(p0.x, p0.y, p0.z + this._gen.lift);
        this._trySetOrigin(this._target, p1);
        this._trySetVelocity(this._target, Vector(this._gen.vx, this._gen.vy, this._gen.vz));
        this._gen.phase = (this._gen.zhold > 0) ? 1 : 2;
        this._schedule(0.0);
        return;
    }

    // Phase 1: keep Z for short hold frames
    if (this._gen.phase == 1) {
        this._trySetVelocity(this._target, Vector(this._gen.vx, this._gen.vy, this._gen.vz * 0.6));
        this._gen.zhold -= 1;
        if (this._gen.zhold <= 0) this._gen.phase = 2;
        this._schedule(0.01);
        return;
    }

    // Phase 2: horizontal push (Z=0) repeated ticks times
    if (this._gen.phase == 2) {
        if (this._gen.ticks <= 0) { this._gen.active = false; this._setPlaying(false); print("[QMF] finished\n"); return; }
        this._trySetVelocity(this._target, Vector(this._gen.vx, this._gen.vy, 0.0));
        this._gen.ticks -= 1;
        this._schedule(this._gen.dt);
        return;
    }
};

// -- chat hook ---------------------------------------------------------------
::QMF.OnGameEvent_player_say <- function(ev) {
    if (!("text" in ev)) return;
    local raw = "" + ev.text, msg = raw.tolower();
    local trimmed = ::QMF._trimSpaces(msg);
    if (trimmed.len() < 4 || trimmed.slice(0,4) != "!qmf") return;

    local toks = split(trimmed, " ");

    // !qmf test
    if (toks.len() >= 2 && toks[1] == "test") { print("[QMF] chat hook OK\n"); return; }

    // !qmf stop
    if (toks.len() >= 2 && toks[1] == "stop") { ::QMF.Stop(); return; }

    // !qmf target <name>
    if (toks.len() >= 3 && toks[1] == "target") { ::QMF.SetTarget(toks[2]); return; }

    // !qmf play [speed=.. dt=.. ticks=.. up=.. lift=.. zhold=..]
    if (toks.len() >= 2 && toks[1] == "play") {
        local speed = 320.0, dt = 0.05, ticks = 10, up = 0.0;
        local lift = null, zhold = null;
        for (local i=2; i<toks.len(); i+=1) {
            local kv = split(toks[i], "=");
            if (kv.len() != 2) continue;
            local k = kv[0].tolower(), v = kv[1];
            if (k == "speed") speed = v.tofloat();
            else if (k == "dt") dt = v.tofloat();
            else if (k == "ticks") ticks = v.tointeger();
            else if (k == "up") up = v.tofloat();
            else if (k == "lift") lift = v.tofloat();
            else if (k == "zhold") zhold = v.tointeger();
        }
        ::QMF.PlayForward(speed, dt, ticks, up, lift, zhold);
        return;
    }
};

// register callback
try { __CollectGameEventCallbacks(::QMF); }
catch (e) { this.OnGameEvent_player_say <- function(ev) { ::QMF.OnGameEvent_player_say(ev); }; }

print(format("[QMF] qm_forward loaded. default target=%s  Use: !qmf target <name>, !qmf play, !qmf stop\n", ::QMF._targetName));
