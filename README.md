<<<<<<< HEAD
=======
Need to edit powerdynamics library. Edit PSSE_BaseMachine

  @parameters begin
  
  status = 1.0, [description="Component status: 1.0 = On, 0.0 = Off"]

----


  [pir, pii] .~ -status * CoB*[sin(delta)  cos(delta); -cos(delta)  sin(delta)] * [id, iq]
>>>>>>> 6bf94dc0c8a230d1c433b8564a07a1eaf3b95d54


      
