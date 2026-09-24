The ten loader plates, in the order they play (2 seconds each).

Save the images here with these exact names, then tell Claude -- it uploads
them to Roblox and pastes the ids into STILLS in SminskiTitle.client.lua.

  plate01_clouds.png        city seen through a break in the clouds
  plate02_aerial.png        the whole town from above, daylight
  plate03_street.png        street corner, character + dog
  plate04_bakery.png        bakery window, trays of buns
  plate05_pizzeria.png      brick oven, chef, topping tubs
  plate06_taxi.png          yellow taxi, passenger getting in
  plate07_construction.png  hard hats, crates, half-built house
  plate08_home.png          apartment, bed, plant, window
  plate09_park.png          park at golden hour, characters on the grass
  plate10_night.png         the city from above after dark  <- the handoff

PNG or JPG both fine. Any size -- they get resized to 1024x576 on the way in
(Roblox caps image uploads at 1024 on the long edge).

plate10 is the important one: the live camera picks the shot up from exactly
that altitude and dives back into the real city, so it has to stay high and
dark or the seam shows.
