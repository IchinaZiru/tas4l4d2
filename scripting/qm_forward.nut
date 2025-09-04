// qm_forward.nut
// Scripted by Ichina

if (!("QMF" in getroottable())) ::QMF <- {};

// Runtime state
::QMF._playing <- false;
::QMF._i <- 0;
::QMF._target <- null;
::QMF._frames <- [];
::QMF._lastPos <- null;
::QMF._lastAng <- null;
::QMF._lastVel <- null;

// Defaults
::QMF._targetName <- "!nick";  // default survivor handle (e.g. nick, ellis, rochelle...)
::QMF._defaultLift <- 16.0;    // vertical lift before jump (units)
::QMF._defaultZHold <- 2;      // frames to keep Z velocity

// --- Utils ---
::QMF._deg2rad <- function(d) { return d * 3.1415926535 / 180.0; };
::QMF._trimSpaces <- function(s) {
    if (typeof s != "string") return s;
    local L = s.len(), i = 0, j = L - 1;
    while (i < L && (s[i] == ' ' || s[i] == '\t')) i++;
    while (j >= i && (s[j] == ' ' || s[j] == '\t')) j--;
    return (i>j) ? "" : s.slice(i, j+1);
};

// Entity resolve helpers (Ent -> FindByName -> null)
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

// Safe setters (with fallbacks)
::QMF._trySetOrigin <- function(ent, pos) {
    try { if (("SetOrigin" in ent)) { ent.SetOrigin(pos); return true; } } catch(e) {}
    try {
        EntFireByHandle(ent, "AddOutput",
            format("origin %.3f %.3f %.3f", pos.x,pos.y,pos.z), 0.0, null, null);
        return true;
    } catch(e2) {}
    return false;
};
::QMF._trySetAngles <- function(ent, ang) {
    try { if (("SnapEyeAngles" in ent)) { ent.SnapEyeAngles(ang); return true; } } catch(e) {}
    try { if (("SetAngles" in ent)) { ent.SetAngles(ang.x, ang.y, ang.z); return true; } } catch(e2) {}
    return false;
};
::QMF._trySetVelocity <- function(ent, vel) {
    try { if (("SetVelocity" in ent)) { ent.SetVelocity(vel); return true; } } catch(e) {}
    // Fallback: basevelocity (helps Z push on some servers)
    try {
        EntFireByHandle(ent, "AddOutput",
            format("basevelocity %.3f %.3f %.3f", vel.x, vel.y, vel.z), 0.0, null, null);
        return true;
    } catch(e2) {}
    return false;
};

// Frame applier
::QMF._applyFrame <- function(fr) {
    if (!this._target || !this._target.IsValid()) return;

    if (this._lastPos == null) this._lastPos = this._target.GetOrigin();
    if (this._lastAng == null) this._lastAng = this._target.GetAngles();
    if (this._lastVel == null) this._lastVel = this._target.GetVelocity();

    local pos = ("pos" in fr && fr.pos) ? fr.pos : null;
    local ang = ("ang" in fr && fr.ang) ? fr.ang : null;
    local vel = ("vel" in fr && fr.vel) ? fr.vel : null;

    if (pos) { if (!::QMF._trySetOrigin(this._target, pos)) pos = this._lastPos; } else { pos = this._lastPos; }
    if (ang) { if (!::QMF._trySetAngles(this._target, ang)) ang = this._lastAng; } else { ang = this._lastAng; }
    if (vel) { ::QMF._trySetVelocity(this._target, vel); } else { vel = this._lastVel; }

    this._lastPos = pos; this._lastAng = ang; this._lastVel = vel;
};

// Playback loop
::QMF._tick <- function() {
    if (!this._playing) return;
    if (this._i >= this._frames.len()) { this._playing = false; print("[QMF] finished\n"); return; }
    local fr = this._frames[this._i++]; this._applyFrame(fr);
    local d = (("dt" in fr) && (typeof fr.dt == "float" || typeof fr.dt == "integer")) ? fr.dt.tofloat() : 0.0;
    DoEntFire("!self", "RunScriptCode", "::QMF._tick()", d, null, null);
};

// API: set target by name ("nick" or "!nick")
::QMF.SetTarget <- function(name) {
    if (this._playing) { print("[QMF] stop first\n"); return false; }
    this._targetName = (name.len() && name[0] == '!') ? name.tolower() : ("!" + name.tolower());
    this._target = null;
    local ok = this._ensureTarget();
    print(format("[QMF] target = %s (%s)\n", this._targetName, ok ? "resolved" : "not found"));
    return ok;
};

// API: play forward (overwrite-safe). If up>0, inject a jump block.
QMF.PlayForward <- function(speed = 320.0, dt = 0.05, ticks = 30, up = 0.0, lift = null, zhold = null) {
    // if already playing, just reset values
    if (QMF.isPlaying && QMF.handle != null) {
        QMF.speed = speed
        QMF.dt = dt
        QMF.ticks = ticks
        QMF.up = up
        QMF._frames = []   // reset frame buffer
        for (local i = 0; i < ticks; i++) {
            local ang = QMF.target.EyeAngles()
            local yaw = ang.y
            local vx = cos(yaw) * speed
            local vy = sin(yaw) * speed
            local vz = up
            QMF._frames.append(Vector(vx, vy, vz))
        }
        QMF._idx = 0
        printl("[QMF] restarted PlayForward speed=" + speed + " dt=" + dt + " ticks=" + ticks + " up=" + up)
        return
    }

    // if not playing, start fresh
    QMF.Stop()
    QMF.speed = speed
    QMF.dt = dt
    QMF.ticks = ticks
    QMF.up = up
    QMF.target = Entities.FindByName(null, "!nick")
    if (QMF.target == null) {
        printl("[QMF] no target found")
        return
    }

    QMF._frames <- []
    for (local i = 0; i < ticks; i++) {
        local ang = QMF.target.EyeAngles()
        local yaw = ang.y
        local vx = cos(yaw) * speed
        local vy = sin(yaw) * speed
        local vz = up
        QMF._frames.append(Vector(vx, vy, vz))
    }

    QMF._idx <- 0
    QMF.isPlaying = true
    QMF.handle = Entities.CreateByClassname("logic_timer")
    QMF.handle.SetInterval(dt)
    QMF.handle.ConnectOutput("OnTimer", function() {
        if (QMF._idx >= QMF._frames.len()) {
            QMF.Stop()
            return
        }
        local vel = QMF._frames[QMF._idx]
        QMF.target.SetVelocity(vel)
        QMF._idx++
    })
    QMF.handle.Enable()
}

::QMF.Stop <- function() { this._playing = false; print("[QMF] stopped\n"); };
::QMF.IsPlaying <- function() { return this._playing; };

// Chat hook
::QMF.OnGameEvent_player_say <- function(ev) {
    if (!("text" in ev)) return;
    local raw = "" + ev.text, msg = raw.tolower();
    local trimmed = ::QMF._trimSpaces(msg);
    if (trimmed.len() < 4 || trimmed.slice(0,4) != "!qmf") return;

    local toks = split(trimmed, " ");

    if (toks.len() >= 2 && toks[1] == "test") { print("[QMF] chat hook OK\n"); return; }
    if (toks.len() >= 2 && toks[1] == "stop") { ::QMF.Stop(); return; }

    if (toks.len() >= 3 && toks[1] == "target") {
        ::QMF.SetTarget(toks[2]);
        return;
    }

    if (toks.len() >= 2 && toks[1] == "play") {
        // defaults
        local speed = 320.0, dt = 0.05, ticks = 10, up = 0.0;
        local lift = null, zhold = null;

        // parse key=val
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

// Register callbacks
try { __CollectGameEventCallbacks(::QMF); }
catch (e) { this.OnGameEvent_player_say <- function(ev) { ::QMF.OnGameEvent_player_say(ev); }; }

print(format("[QMF] qm_forward loaded. default target=%s  Use: !qmf target <name>, !qmf play, !qmf stop\n", ::QMF._targetName));
