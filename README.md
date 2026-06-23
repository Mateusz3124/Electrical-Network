Need to edit powerdynamics library. Edit PSSE_BaseMachine

  @parameters begin
  
  status = 1.0, [description="Component status: 1.0 = On, 0.0 = Off"]

----


  [pir, pii] .~ -status * CoB*[sin(delta)  cos(delta); -cos(delta)  sin(delta)] * [id, iq]


      
