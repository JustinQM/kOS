CLEARSCREEN.
SHIP:DELTAV:FORCECALC .
LOCAL start_dv IS SHIP:DELTAV:VACUUM .
PRINT "Total DeltaV is " + start_dv .

PRINT "Countdown Starting!".

LOCK THROTTLE TO 1.0 .
SET target_orbit TO 100000 .

FROM {LOCAL countdown is 3.} UNTIL countdown = 0 STEP {SET countdown TO countdown - 1.} DO 
{
    PRINT "..." + countdown.
    WAIT 1.
}

LOCK STEERING TO UP .

WHEN MAXTHRUST = 0 or stage:resourcesLex["LiquidFuel"]:amount = 0 THEN
{
    PRINT "STAGING!" .
    STAGE .
    RETURN TRUE .
}

SET my_steer TO HEADING(90,90) .
LOCK STEERING TO my_steer .
UNTIL SHIP:APOAPSIS > target_orbit
{
    IF SHIP:VELOCITY:SURFACE:MAG >= 200 and SHIP:ALTITUDE <= 10000
    {
        LOCK THROTTLE TO 0.325 .
    }.
    ELSE IF SHIP:VELOCITY:SURFACE:MAG <= 200 and SHIP:ALTITUDE <= 10000
    {
        LOCK THROTTLE TO 1.0 .
    }
    ELSE IF SHIP:ALTITUDE >= 10000 and SHIP:ALTITUDE <= 35000 and SHIP:VELOCITY:SURFACE:MAG >= 350
    {
        LOCK THROTTLE TO 0.4 .
        SET my_steer TO HEADING(90,55) .
    }
    ELSE IF SHIP:ALTITUDE >= 10000 and SHIP:ALTITUDE <= 35000 and SHIP:VELOCITY:SURFACE:MAG <= 350
    {
        SET my_steer TO HEADING(90,60) .
        LOCK THROTTLE TO 0.75 .
    }

    IF SHIP:ALTITUDE >= 35000
    {
        SET my_steer TO HEADING(90,30) .
        LOCK THROTTLE TO 0.75 .
    }

    PRINT ROUND(SHIP:APOAPSIS,0) AT (0,16) .
    WAIT 0.5 .
}.

LOCK THROTTLE TO 0.0 .
LOCK STEERING TO Ship:PROGRADE .
SHIP:DELTAV:FORCECALC .
LOCAL end_dv IS SHIP:DELTAV:VACUUM .
PRINT "start_dv: " + start_dv + " end_dv: " + end_dv .
PRINT "Total Used DeltaV: " + (start_dv - end_dv) .

PRINT "Waiting until burn..." .

SET burn_ut TO TIME:SECONDS + ETA:APOAPSIS.
SET orbit_node TO NODE(burn_ut, 0, 0, 0).
ADD orbit_node.

print "Creating Node...".
SET i TO 0 .
SET max_i TO 1200 .

SET dv TO orbit_node:PROGRADE .
SET dir TO 1 .
SET step TO 50 .
SET min_step TO 0.01 .
SET tolerance TO 10 .
SET final_tol TO 0.1 .

SET best_diff TO ABS(orbit_node:ORBIT:APOAPSIS - orbit_node:ORBIT:PERIAPSIS) .

SET mode TO "DV" .
SET dt_step TO 1.0 .
SET min_dt TO 0.01 .

SET stagnant_local TO 0 .
SET stagnant_global TO 0 .
SET stagnant_global_limit TO 300 .
SET eps_improve TO 0.01 .
SET print_row TO 18 .

SET t0 TO TIME:SECONDS .
SET max_runtime TO 20 .   // seconds

IF best_diff <= tolerance
{
    print "Already circular within tolerance with dv=" + dv + " m/s." .
    WAIT 0.1 .
}

UNTIL i >= max_i
{
    IF TIME:SECONDS - t0 > max_runtime { BREAK . }

    IF mode = "DV"
    {
        SET trial_dv TO dv + dir * step .
        SET orbit_node:PROGRADE TO trial_dv .
        WAIT 0. .
        SET trial_diff TO ABS(orbit_node:ORBIT:APOAPSIS - orbit_node:ORBIT:PERIAPSIS) .

        IF trial_diff + eps_improve < best_diff
        {
            SET dv TO trial_dv .
            SET stagnant_local TO 0 .
            SET stagnant_global TO 0 .
            SET best_diff TO trial_diff .

            IF best_diff <= final_tol { BREAK . }

            IF step > 5 AND best_diff < 2000 { SET step TO step / 2 . }.
            IF step > 1 AND best_diff < 200  { SET step TO step / 2 . }.
        }
        ELSE
        {
            SET orbit_node:PROGRADE TO dv .
            WAIT 0. .
            SET dir TO -dir .
            SET step TO MAX(step / 2, min_step) .
            SET stagnant_local TO stagnant_local + 1 .
            SET stagnant_global TO stagnant_global + 1 .

            IF (stagnant_local >= 6 OR step <= min_step) AND best_diff > final_tol
            {
                SET mode TO "TIME" .
                SET dir TO 1 .
                SET stagnant_local TO 0 .
            }.
        }
    }
    ELSE
    {
        SET old_t TO orbit_node:TIME .
        SET trial_t TO old_t + dir * dt_step .
        SET orbit_node:TIME TO trial_t .
        WAIT 0. .
        SET trial_diff TO ABS(orbit_node:ORBIT:APOAPSIS - orbit_node:ORBIT:PERIAPSIS) .

        IF trial_diff + eps_improve < best_diff
        {
            SET best_diff TO trial_diff .
            SET stagnant_local TO 0 .
            SET stagnant_global TO 0 .

            IF best_diff <= final_tol { BREAK . }

            IF dt_step > 0.1 AND best_diff < 500 { SET dt_step TO dt_step / 2 . }.
            IF dt_step > 0.05 AND best_diff < 50 { SET dt_step TO dt_step / 2 . }.
        }
        ELSE
        {
            SET orbit_node:TIME TO old_t .
            WAIT 0. .
            SET dir TO -dir .
            SET dt_step TO MAX(dt_step / 2, min_dt) .
            SET stagnant_local TO stagnant_local + 1 .
            SET stagnant_global TO stagnant_global + 1 .

            IF (stagnant_local >= 6 OR dt_step <= min_dt)
            {
                SET mode TO "DV" .
                SET dir TO 1 .
                SET stagnant_local TO 0 .
            }.
        }
    }

    IF (step <= min_step AND dt_step <= min_dt) { BREAK . }
    IF stagnant_global >= stagnant_global_limit { BREAK . }

    IF MOD(i, 10) = 0 
    { 
        PRINT "i=" + i + " |Ap-Pe|=" + ROUND(best_diff,2) + " step=" + step + " dt=" + ROUND(dt_step,3) + "   " AT (0,print_row) . 
        SET print_row TO print_row + 1 .
        IF print_row > 28 { SET print_row TO 18 . }
    }

    SET i TO i + 1 .
}

print "Done after " + i + " iters. dv=" + ROUND(dv,2) + " m/s, |Ap-Pe|=" + ROUND(best_diff,2) + " m, step=" + step + " m/s, dt_step=" + ROUND(dt_step,3) + " s." .

SET ND TO NEXTNODE .

SET DV_TOL TO 0.8 .          
SET FEATHER_DV TO 20 .       
SET FEATHER_TIME TO 4 .      
SET STAG_LIMIT TO 40 .       

SET MAX_ACC TO MAX(0.01, SHIP:MAXTHRUST / SHIP:MASS) .
SET BURN_DUR TO ND:DELTAV:MAG / MAX_ACC .
SET START_UT TO TIME:SECONDS + MAX(0, ND:ETA - (BURN_DUR / 2)) .

LOCK STEERING TO ND:DELTAV .
WAIT UNTIL VANG(ND:DELTAV, SHIP:FACING:VECTOR) < 2 OR TIME:SECONDS > START_UT - 1 .

WAIT UNTIL TIME:SECONDS >= START_UT .

SET last_dv TO ND:DELTAV:MAG .
SET stag TO 0 .

UNTIL ND:DELTAV:MAG <= DV_TOL
{
    SET MAX_ACC TO MAX(0.01, SHIP:MAXTHRUST / SHIP:MASS) .

    IF VANG(ND:DELTAV, SHIP:FACING:VECTOR) > 5
    {
        LOCK THROTTLE TO 0 .
        LOCK STEERING TO ND:DELTAV .
        WAIT 0.1 .
        //no continue keyword...
    }

    IF ND:DELTAV:MAG > FEATHER_DV AND ND:ETA > FEATHER_TIME
    {
        LOCK THROTTLE TO 1 .
    }
    ELSE
    {
        SET t_req TO ND:DELTAV:MAG / MAX_ACC .
        SET t_target TO FEATHER_TIME .
        SET t_ratio TO t_req / t_target .
        SET tset TO MIN( MAX(t_ratio, 0.15), 0.80 ) .
        LOCK THROTTLE TO tset .
    }

    IF ND:DELTAV:MAG >= last_dv - 0.02
    {
        SET stag TO stag + 1 .
    }
    ELSE
    {
        SET stag TO 0 .
    }
    SET last_dv TO ND:DELTAV:MAG .
    print ("[Burn] Last DV: " + last_dv + " DV:MAG: " + ND:DELTAV:MAG) AT (0,17) .

    IF stag >= STAG_LIMIT { BREAK . }

    WAIT 0.1 .
}

LOCK THROTTLE TO 0 .
UNLOCK STEERING .
UNLOCK THROTTLE .
REMOVE ND .

PRINT "COMPLETE! (maybe)" .

LOCK THROTTLE TO 0.0 .
