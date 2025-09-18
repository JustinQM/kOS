//"jst_orbital.ks"

//"-----------------------------------------------------------------------------------------"
//"USABLE FUNCTIONS"

//"get_circular_orbit_node(void)" -> Node
//      "Creates a circular orbit out of the current ships Apoapsis"

//"generic_launch(height) -> void"
//"Parameters:"
//"target_apoapsis -> target apoapsis of resulting launch (this does not mean a orbit)"
//"Does not handling staging"

//"FUNCTION exec_node(Node) -> Void"
//"Executes a node"

//"-----------------------------------------------------------------------------------------"

// ---- Helpers: calculate density at given height
function air_density 
{
    parameter p_alt is ship:altitude .
    // pressure (atm -> pa):
    local p_atm is ship:body:atm:altitudepressure(p_alt) .
    local p_pa  is p_atm * constant:atmtokpa * 1000 .
    // temperature (k):
    local t     is ship:body:atm:alttemp(p_alt) .
    if (not ship:body:atm:exists) or (p_atm <= 0) or (t <= 0) 
    {
        return 0.
    }.
    // molar mass (kg/mol) and universal gas constant (j/mol/k):
    local m     is ship:body:atm:molarmass .
    local ru    is constant:idealgas .
    // density ρ = p*m / (r*t). if above atmo, p_atm=0 → ρ=0:
    local rho   is (p_pa * m) / (ru * t) .
    return rho.
}.

function pitch_floor_from_q 
{
    parameter q_now .
    parameter q_cap .

    // Atmosphere fraction from density (planet-agnostic)
    local rho_now is air_density(ship:altitude).
    local rho_sl  is air_density(0).

    //if air density is more then 2x kerbin, cap it to that for calculations
    if rho_sl > 2 { set rho_sl to 2 .}

    local atm_frac is 0.
    if rho_sl > 0 { set atm_frac to min(1, max(0, rho_now / rho_sl)). }.


    // q fraction; allow a bit over-cap awareness
    local qf is 0.
    if q_cap > 0 { set qf to min(1.5, max(0, q_now / q_cap)). }.

    // "Openness" from q 
    local x is (0.90 - qf) / 0.7.
    if x < 0 { set x to 0. }.
    if x > 1 { set x to 1. }.
    local g_q is x * x * (3 - 2 * x).

    // Thin-air also opens things up a bit 
    local g_cap is (1 - atm_frac) * 0.85.
    if g_cap < 0.15 { set g_cap to 0.15. }.
    if g_cap > 1.0 { set g_cap to 1.0. }.

    //sanity check: if still in the first 10% of the atmosphere, disregard q
    if ship:body:atm:exists and ship:altitude / ship:body:atm:height < 0.10
    {
        set g_q to 0.
    }
    
    // Combine: q dominates, density secondary 
    local g is max(g_q, g_cap * 0.8).
    //if a super dense atmosphere, scale atm aggressively to leave it faster
    if rho_sl >= 2 { local g is max(g_q, g_cap * min(1,g_q)) . }


    print "rho_now: " + ROUND(rho_now,3) AT(0,25). 
    print "rho_sl: " + ROUND(rho_sl,3) AT(0,26). 
	if ship:body:atm:exists
	{
    	print "percent through atmosphere: " + ROUND(ship:altitude / ship:body:atm:height, 3) + "%" AT(0,27). 

	}
    print "Q: " + ROUND(g_q,3) AT(0,28). 
    print "ATM: " + ROUND(g_cap,3) AT(0,29).
    print "CHOSEN: " + ROUND(g,3) AT(0,30).

    // Allowed tilt-from-vertical (deg)
    local tilt_min is 5.                  // never perfectly straight up
    local tilt_max is 85.                 // don't command below ~5° pitch
    local tilt     is tilt_min + (tilt_max - tilt_min) * g.

    // Mild TWR nudge 
    local sg   is ship:body:mu / ((ship:body:radius)^2).
    local twr0 is ship:maxthrust / (ship:mass * sg).
    set tilt to tilt + min(4, max(0, (twr0 - 1.6) * 6)).

    //don't tilt if we are still in full atmosphere
    if atm_frac > 0.9 { set tilt to 0 .}

    // Convert to your pitch convention
    local pitch_cmd is 90 - min(88, max(tilt_min, tilt)).

    // Require vertical thrust component ≳ 1.05*g to keep climbing
    local g_now is ship:body:mu / ((ship:body:radius + ship:altitude)^2).
    local a_thr is ship:availablethrust / max(0.001, ship:mass).
    local req   is (1.05 * g_now) / max(0.001, a_thr).
    if req < 0 { set req to 0. }.
    if req > 0.98 { set req to 0.98. }.
    local pitch_guard is arcsin(req).    // degrees

    if (ship:altitude < 0.5 * ship:body:atm:height) and (qf > 0.25) {
        set pitch_guard to max(pitch_guard, 12).
    }.

    set pitch_cmd to max(pitch_cmd, pitch_guard).

    return max(0, min(88, pitch_cmd)).
}.


function get_circular_orbit_node
{
    print "creating circular orbit node...".

    set burn_ut to time:seconds + eta:apoapsis.
    set orbit_node to node(burn_ut, 0, 0, 0).
    add orbit_node.

    set i to 0 .
    set max_i to 1200 .

    set dv to orbit_node:prograde .
    set dir to 1 .
    set step to 50 .
    set min_step to 0.01 .
    set tolerance to 10 .
    set final_tol to 0.1 .

    set best_diff to abs(orbit_node:orbit:apoapsis - orbit_node:orbit:periapsis) .

    set mode to "dv" .
    set dt_step to 1.0 .
    set min_dt to 0.01 .

    set stagnant_local to 0 .
    set stagnant_global to 0 .
    set stagnant_global_limit to 300 .
    set eps_improve to 0.01 .
    set print_row to 18 .

    set t0 to time:seconds .
    set max_runtime to 20 .   // seconds

    if best_diff <= tolerance
    {
        print "already circular within tolerance with dv=" + dv + " m/s." .
        wait 0.1 .
    }

    until i >= max_i
    {
        if time:seconds - t0 > max_runtime { break . }

        if mode = "dv"
        {
            set trial_dv to dv + dir * step .
            set orbit_node:prograde to trial_dv .
            wait 0. .
            set trial_diff to abs(orbit_node:orbit:apoapsis - orbit_node:orbit:periapsis) .

            if trial_diff + eps_improve < best_diff
            {
                set dv to trial_dv .
                set stagnant_local to 0 .
                set stagnant_global to 0 .
                set best_diff to trial_diff .

                if best_diff <= final_tol { break . }

                if step > 5 and best_diff < 2000 { set step to step / 2 . }.
                if step > 1 and best_diff < 200  { set step to step / 2 . }.
            }
            else
            {
                set orbit_node:prograde to dv .
                wait 0. .
                set dir to -dir .
                set step to max(step / 2, min_step) .
                set stagnant_local to stagnant_local + 1 .
                set stagnant_global to stagnant_global + 1 .

                if (stagnant_local >= 6 or step <= min_step) and best_diff > final_tol
                {
                    set mode to "time" .
                    set dir to 1 .
                    set stagnant_local to 0 .
                }.
            }
        }
        else
        {
            set old_t to orbit_node:time .
            set trial_t to old_t + dir * dt_step .
            set orbit_node:time to trial_t .
            wait 0. .
            set trial_diff to abs(orbit_node:orbit:apoapsis - orbit_node:orbit:periapsis) .

            if trial_diff + eps_improve < best_diff
            {
                set best_diff to trial_diff .
                set stagnant_local to 0 .
                set stagnant_global to 0 .

                if best_diff <= final_tol { break . }

                if dt_step > 0.1 and best_diff < 500 { set dt_step to dt_step / 2 . }.
                if dt_step > 0.05 and best_diff < 50 { set dt_step to dt_step / 2 . }.
            }
            else
            {
                set orbit_node:time to old_t .
                wait 0. .
                set dir to -dir .
                set dt_step to max(dt_step / 2, min_dt) .
                set stagnant_local to stagnant_local + 1 .
                set stagnant_global to stagnant_global + 1 .

                if (stagnant_local >= 6 or dt_step <= min_dt)
                {
                    set mode to "dv" .
                    set dir to 1 .
                    set stagnant_local to 0 .
                }.
            }
        }

        if (step <= min_step and dt_step <= min_dt) { break . }
        if stagnant_global >= stagnant_global_limit { break . }

        if mod(i, 10) = 0 
        { 
            set print_row to print_row + 1 .
            if print_row > 28 { set print_row to 18 . }
        }

        set i to i + 1 .
    }

    print "done after " + i + " iters. dv=" + round(dv,2) + " m/s, |Ap-Pe|=" + round(best_diff,2) + " m, step=" + step + " m/s, dt_step=" + round(dt_step,3) + " s." .

    remove orbit_node .
    return orbit_node .
}


function exec_node
{
    print "waiting to execute node..." .
    parameter nd is nextnode .

    lock max_acc to ship:maxthrust / ship:mass .

    set burn_duration to nd:deltav:mag / max_acc .

    unlock steering.
    sas on .
    wait 0 .
    set sasmode to "maneuver".
    wait until nd:eta <= (burn_duration/2 + 60) .

    wait until vang(nd:deltav, ship:facing:vector) < 0.25 .

    wait until nd:eta <= (burn_duration / 2) .

    set t_cmd to 0 .
    lock throttle to t_cmd .

    print "executing node..." .
    set done to false .
    set dv0 to nd:deltav .
    until done
    {
        if max_acc = 0
        {
            set t_cmd to tcmd .
        }
        else
        {
            set t_cmd to min(nd:deltav:mag / max_acc, 1) .
        }
        if vdot(dv0, nd:deltav) < 0
        {
            lock throttle to 0 .
            break .
        }

        if nd:deltav:mag < 0.1
        {
            wait until vdot(dv0, nd:deltav) < 0.5 .
            lock throttle to 0 .
            set done to true .
        }
    }

    print "execution complete!" .
    unlock steering .
    unlock throttle .
    sas off .
    wait 0.5 .

    remove nd .

    set ship:control:pilotmainthrottle to 0 .

    return .
}

function dyn_q_cap 
{
    parameter MACH_CAP is 1.0.

    local rho_sl is air_density(0).
    if rho_sl <= 0 { return 1e9. }.

    // Reference Kerbin sea-level density (kg/m^3)
    local RHO_REF is 1.225.
    // Nominal Kerbin cap (Pa)
    local BASE_Q  is 30000.

    // Gentle scaling to avoid extremes on very thick/thin atmospheres
    local scale  is (rho_sl / RHO_REF) ^ 0.5.
    local q_cap  is BASE_Q * scale.

    // Clamp to a safe, realistic band (Pa)
    if q_cap < 15000 { set q_cap to 15000. }.
    if q_cap > 40000 { set q_cap to 40000. }.

    print "Calculated q_cap is: " + q_cap .
    return q_cap.
}

//generic launch function
//parameters:
//target_apoapsis -> target apoapsis of resulting launch (this does not mean a orbit)

// (optional) Q_TGT_FRAC — Dynamic-pressure setpoint (0–1, unitless; default 0.50).
// The autopilot tries to keep q ≈ Q_TGT_FRAC × q_max by modulating throttle.
// ↑ Higher value → allows higher MaxQ → pushes harder through the air (faster climb, more aero loads/drag).
// ↓ Lower value  → gentler ascent → less aero stress but more gravity losses.
// Tips: High-TWR, sturdy rockets often like 0.60–0.70. Fragile/fairing-limited or Eve-like atmospheres may prefer 0.45–0.55.

// (optional) a_cap — Acceleration comfort cap in m/s^2 (default 40).
// Throttle will be limited so commanded acceleration ≲ a_cap (relaxes in thin air).
// Purpose: avoid huge G spikes (and big q spikes) on high-TWR stacks.
// Raise it for vacuum-heavy upper stages or low-TWR lifters; lower it for delicate payloads.

// (optional) LIFTOFF_V_TARGET — leave prelaunch mode once you reach this speed (m/s)

//does not handling staging
function generic_launch
{
    parameter target_apoapsis .
    parameter LIFTOFF_V_TARGET is 150 .
    parameter LIFTOFF_TWR_MIN is 1.50 .   
    parameter LIFTOFF_TWR_MAX is 1.80 .
    parameter Q_TGT_FRAC is 0.50 .
    parameter a_cap is 40 .
    print "starting launch to " + target_apoapsis .

    local body_r is ship:body:radius .               //body radius
    local ah is ship:body:atm:height .          //atmosphere height
    local mu is ship:body:mu .                  //gravitational parameter of body
    local sg is mu / (body_r^2) .          //surface gravity
    local lock h to ship:altitude .                    //ship altitude
    local lock p to air_density(h) .       //density at specific altitude
    local lock m to ship:mass .
    local lock tmax to ship:maxthrust .
    local lock t to ship:availablethrust .
    local lock vel to ship:velocity:surface:mag .
    local lock y to ship:velocity:surface .
    local twr0 is tmax / (m * sg) .


    //step 0: "calculate kick and kick direction"
    local kick_deg is max(0.4, min(1.2, 1.2 - 0.5 * (twr0 - 1.2))) .
    local kick_rad is kick_deg * constant:degtorad .

    local lock upv to ship:up:vector .
    local lock northv to north:vector .
    local east_nom is vcrs(northv, upv):normalized .

    local body_spin is ship:body:angularvel .
    local east_spin is vcrs(upv, body_spin) .

    if east_spin:mag < 1e-6 {set east_spin to east_nom .} else {set east_spin to east_spin:normalized .}

    set kick_dir to (upv*cos(kick_rad) + east_spin*sin(kick_rad)):normalized.
    set kick_heading to mod((arctan2( vdot(kick_dir, east_nom), vdot(kick_dir, northv) ) + 360), 360).

    local pre_tilt is max(0.3, min(0.8, 1.2 - 0.6 * (twr0 - 1.0))).

    //step 0.1: set q and qmax (thrust limiter)
    local lock rho to p .
    local lock q_value to 0.5 * rho * vel^2 .
    local q_max is dyn_q_cap() .
    local lock q_frac to min(1, max(0, q_value / q_max)).

    //step 0.2: "save on the pad roll"
    local pad_up0 is ship:up:vector.
    local pad_top0 is ship:facing:topvector.
    if abs(vdot(pad_top0, pad_up0)) > 0.98 { set pad_top0 to ship:facing:starvector. }.

    // ===== step 1: liftoff =====
    set tcmd to 1.0.
    lock throttle to tcmd.
    wait 0.25 . //give a little kick to start
    set kick_done to false.
    until kick_done
    {

        // Keep vertical + hold pad roll 
        local upv_now is ship:up:vector.
        local roll_ref is (pad_top0 - (vdot(pad_top0, upv_now) * upv_now)).
        if roll_ref:mag < 1e-6 { set roll_ref to heading(0,0):vector.}. 
        set roll_ref to roll_ref:normalized.
        lock steering to lookdirup(upv_now, roll_ref).

        // Pre-tilt once moving a bit 
        if vel >= LIFTOFF_V_TARGET / 2 { lock steering to heading(kick_heading, 90 - pre_tilt).}

        //throttle caps
        local q_target is Q_TGT_FRAC * q_max.

        // cap_q: linear clamp (if q is 2× target -> ≤0.5 throttle)
        local cap_q is 1.0.
        if q_value > 0 { set cap_q to min(1.0, max(0.25, q_target / q_value)). }.

        // cap_a: accel cap 
        local cap_a is min(1.0, a_cap / max(1, ship:maxthrust / m)).

        // Base command = conservative of both caps
        local t_raw is min(cap_q, cap_a) .

        local dcut  is 0.08.
        local drise is 0.02.
        if defined tcmd {} else { set tcmd to 1.0. }.

        if (q_value > 1.10 * q_target) and (t_raw < tcmd)
        {
          if tcmd - t_raw > dcut { set t_raw to tcmd - dcut. }.
        }
        else
        {
          if t_raw > tcmd + drise { set t_raw to tcmd + drise. }.
          if t_raw < tcmd - drise { set t_raw to tcmd - drise. }.
        }

        //exit conditions
        if vel >= LIFTOFF_V_TARGET { set kick_done to true. }. 
        if q_frac >= 0.60 { set kick_done to true. }.

        set tcmd to max(0.0, min(1.0, t_raw)).
        lock throttle to tcmd.    
        WAIT 0.

    }

    //handoff
    lock steering to lookdirup(ship:velocity:surface:normalized, upv).
    set prev_tcmd to tcmd.

    print "starting gravity turn..." .

    until (ship:apoapsis >= target_apoapsis)
    {

        //==================== PITCH ====================
        // pitch_now (deg) from vertical-speed / speed
        local v_up is vdot(y, upv).
        local s    is choose (v_up/vel) IF (vel > 0) ELSE 1.
        if s >  1 { set s to  1. }.
        if s < -1 { set s to -1. }.
        local pitch_now is arcsin(s).

        // New floor: never increases—only eases downward
        local pf_target is pitch_floor_from_q(q_value, q_max).
        if defined pf_cmd {} else { set pf_cmd to pf_target. }.

        // Ease the floor downward. Scale a bit by density so it’s “sharper” when air is thick.
        local rho_now is air_density(ship:altitude).
        local rho_sl  is air_density(0).
        local atm_frac is choose min(1, max(0, rho_now / rho_sl)) IF (rho_sl > 0) ELSE 0.

        local qf_now is 0.
        if q_max > 0 { set qf_now to min(1, max(0, q_value / q_max)). }.

        local rate is 0.6 + 0.9 * (1 - atm_frac) + 1.2 * (1 - qf_now) .

        if defined last_t_pf {} else { set last_t_pf to time:seconds. }.
        local dt_pf is max(0.02, time:seconds - last_t_pf).  set last_t_pf to time:seconds.
        // Allow a small rise of the floor in early, low-q regime if we fell below it
        set last_t_pf to time:seconds.

        set pf_cmd to max(pf_target, (pf_cmd - rate * dt_pf)). // never “stand up”
        if atm_frac = 0 and q_frac < 0.05 { set pf_cmd to pf_target .} //if in a full vacuum, lock onto target

        // AoA guard: 
        local aoa is vang(ship:facing:vector, ship:velocity:surface:vec).
        if aoa > 5 { set pf_cmd to max(0, pf_cmd - 0.5). }

        // Steer: near the floor → go surface prograde; otherwise blend toward floor
        local band is 1.0.
        if abs(pitch_now - pf_cmd) <= band 
        {
            lock steering to lookdirup(ship:velocity:surface:normalized, upv).
        }
        else
        {
            local floor_dir is heading(kick_heading, pf_cmd):vector.
            local pro_dir   is ship:velocity:surface:normalized.

            // Positive error -> we're too flat (pitch_now < pf_cmd): bias strongly to floor.
            local err is pf_cmd - pitch_now.
            if err > 0 
            {
                // pull-up weight grows a bit in thin air (lower aero penalty)
                local w is 0.70 + 0.20 * (1 - atm_frac). // 0.70..0.90
                if w > 0.90 { set w to 0.90. }.
                if w < 0.60 { set w to 0.60. }.
                local blend_dir is (w * floor_dir + (1 - w) * pro_dir):normalized.
                lock steering to lookdirup(blend_dir, upv).
            }
            else
            {
                // too steep (pitch_now > pf_cmd): keep it gentle unless in vacuum
                local blend_dir is floor_dir .
                if atm_frac = 0 and q_frac < 0.05 
                { 
                    local blend_dir is (0.75 * floor_dir + 0.65 * pro_dir):normalized. 
                } 
                else 
                { 
                    local blend_dir is (0.35 * floor_dir + 0.65 * pro_dir):normalized. 
                }
                lock steering to lookdirup(blend_dir, upv).
            }
        }
        //==================== THROTTLE ====================
        // 1) MaxQ control by throttle 
        local q_target   is Q_TGT_FRAC * q_max. // e.g., 0.5 * 25kPa = 12.5kPa
        local cap_q is 1.0.
        if q_value > 0 
        {
            local ratio is q_target / q_value.
            // Linear clamp: if q is 2× target, we allow ≤0.5 throttle, etc.
            set cap_q to min(1.0, max(0.25, ratio)).
        }

        // 2) accel cap 
        local cap_a is min(1.0, a_cap / max(1, ship:maxthrust / m)).

        // Base command = conservative of both caps
        local t_raw is min(cap_q, cap_a) .

        // ---- dynamic rate limit: cut fast when q is high, rise gently otherwise ----
        local dcut  is 0.08.   // per tick, large step down when q is hot
        local drise is 0.02.   // per tick, gentle step up/down otherwise
        if defined prev_tcmd {} else { set prev_tcmd to 1.0. }.

        if (q_value > 1.10 * q_target) and (t_raw < prev_tcmd) 
        {
          // Let throttles drop quickly to arrest q spikes
          if prev_tcmd - t_raw > dcut { set t_raw to prev_tcmd - dcut. }.
        } 
        else 
        {
          // Normal slew
          if t_raw > prev_tcmd + drise { set t_raw to prev_tcmd + drise. }.
          if t_raw < prev_tcmd - drise { set t_raw to prev_tcmd - drise. }.
        }

        set tcmd to max(0.0, min(1.0, t_raw)).
        lock throttle to tcmd.
        set prev_tcmd to tcmd.

        //debug print
        print "debug print --------------------------:" AT(0,15) .
        print "mission time: " + time:seconds AT(0,16).
        print "rho: " + round(rho,3) + "  v: " + round(vel,3) AT(0,17).
        print "q: " + round(q_value,0) + "  q_frac: " + round(q_frac,2) AT(0,18) .
        print ("apo: " + round(ship:apoapsis,0) + " | target apo: " + target_apoapsis) AT(0,19)  .
        print "pitch_now: " + round(pitch_now,2) + "  pf_target: " + round(pf_target,2) + "  pf_cmd: " + round(pf_cmd,2) AT(0,20) .
        print "alt: " + round(ship:altitude,2) AT(0,21) .
        print "ETA_Ap: " + round(eta:apoapsis,1) + "s  tcmd: " + round(tcmd,2) + "  cap_q: " + round(cap_q,2) + "  cap_a: " + round(cap_a,2) AT(0,22) .
        print "--------------------------------------:" AT(0,23) .

    } 

	unlock steering .
    wait 0 .
    print "launch to " + target_apoapsis + " complete!" .
    return .
}
