runpath("jst_orbital.ks").

CLEARSCREEN .
SHIP:DELTAV:FORCECALC .
LOCAL start_dv IS SHIP:DELTAV:VACUUM .
PRINT "Total DeltaV is " + start_dv .

WHEN STAGE:DELTAV:CURRENT < 0.1 THEN
{
    STAGE .
    WAIT 0 .
    RETURN TRUE .
}

generic_launch(169169).

LOCK THROTTLE TO 0 .

WAIT UNTIL SHIP:ALTITUDE > 70000 .

set my_node to get_circular_orbit_node().

unlock steering.
sas ON.
wait 0.001.
set sasmode to "MANEUVER".

set max_accel to ship:maxthrust/ship:mass.
set burn_time to my_node:deltav:mag/max_accel.

wait until my_node:eta <= (burn_time/2).

set done to false.
set initial_deltav to my_node:deltav.

lock throttle to 1.
wait until my_node:deltav:mag < 80.
lock throttle to my_node:deltav:mag / 80 + 0.01.
wait until vdot(initial_deltav, my_node:deltav) < 0.
lock throttle to 0.

remove my_node.


SHIP:DELTAV:FORCECALC .
LOCAL end_dv IS SHIP:DELTAV:VACUUM .
PRINT "start_dv: " + start_dv + " end_dv: " + end_dv .
PRINT "Total Used DeltaV: " + (start_dv - end_dv) .
