runpath("jst_orbital.ks") .

function main
{
    clearscreen .
    ship:deltav:forcecalc .
    local start_dv is ship:deltav:vacuum .
    print "total deltav is " + start_dv .
    from {local countdown is 3.} until countdown = 0 step {set countdown to countdown - 1.} do 
    {
        print "..." + countdown.
        wait 1 .
    }

    lock throttle to 1.0 .
    //when availablethrust = 0 or (stage:resourceslex["liquidfuel"]:amount = 0) then
    //{
        //stage .
        //wait 0.5 .
        //return true .
    //}
    WHEN STAGE:DELTAV:CURRENT < 0.1 THEN
    {
        STAGE .
        WAIT 0 .
        RETURN TRUE .
    }

    local apo_target is 500000 .
    generic_launch(apo_target) .
    lock throttle to 0.0 .
    print "waiting until out of atmosphere..." .
    wait until ship:altitude > 70000 .
    set my_node to get_circular_orbit_node() .
    add my_node .
    exec_node(my_node) .
    lock throttle to 0.0 .

    //"ending logging"
    ship:deltav:forcecalc .
    local end_dv is ship:deltav:vacuum .
    print "start_dv: " + start_dv + " end_dv: " + end_dv .
    print "total used deltav: " + (start_dv - end_dv) .

}

main() .
