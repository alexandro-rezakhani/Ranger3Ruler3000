-- Start of Global Scope -------------------------------------------------------

-- If you want to let this script set a configuration keep it true
-- If you have already configured the camera using Stream Setup set to false
local setCameraConfig = true

-- View to show images from Ruler3000 or Ranger3
local view = View.create("View1")

-- Program state variables
---@type Image.Provider.GigEvision.Ranger3
local camera = nil
local cameraID = nil

--End of Global Scope-----------------------------------------------------------

--Start of Function and Event Scope---------------------------------------------

local function startsWith(str, match)
    return str:sub(1, #match) == match
end

local function isRangerOrRuler(model)
    return startsWith(model, "Ranger") or startsWith(model, "Ruler")
end

local function connectToRangerOrRuler()
    -- Scan network and connect to the first available Ranger/Ruler camera.
    -- If reconnecting, find the previously connected camera.
    while camera == nil do
        print("Scanning for cameras..")
        local foundCameras = Image.Provider.GigEVision.Discovery.scanForCameras()
        if #foundCameras > 0 then
            for i = 1, 1, #foundCameras do
                print("Discovered camera: " .. foundCameras[i]:getID() .. " (" ..
                    foundCameras[i]:getAccessStatus() .. ")")
                if foundCameras[i]:getAccessStatus() == "AVAILABLE" then
                    if isRangerOrRuler(foundCameras[i]:getModel()) then
                        if cameraID == nil or cameraID == foundCameras[i]:getID() then
                            camera = Image.Provider.GigEVision.Ranger3.connectTo(foundCameras[i])
                            if camera == nil then
                                print("Failed to connect to " .. foundCameras[i]:getID())
                            else
                                break
                            end
                        end
                    end
                end
            end
        end
        if camera == nil then
            if cameraID == nil then
                print("Found no available Ranger/Ruler to connect to or failed to connect," ..
                    "re-scan in a few seconds..")
            else
                print("Could not find " .. cameraID .. " among discovered cameras or failed " ..
                    "to connect, re-scan in a few seconds..")
            end
            Script.sleep(5000)
        else
            if cameraID == nil then
                cameraID = camera:getID()
            end
            print("Connected to " .. cameraID)
        end
    end
end

local function registerEventHandler(event, handler)
    local ok = camera:register(event, handler)
    if ok == false then
        print("Error: failed to connect handler for event " .. event)
    end
    return ok
end

---@param frame Image.Provider.GigEVision.Ranger3.Frame
local function onNewFrame(frame)
    print("Frame received.")
    local rangeImage = frame:getRangeImage()
    local reflectanceImage = frame:getReflectanceImage()

    -- Do something with images, then release frame buffer
    view:addHeightmap({rangeImage, reflectanceImage}, nil, {"Reflectance"})
    view:present()

    frame:release()
end

local function onLogMessage(cameraID, timestamp, level, msg)
    print("[" .. timestamp .. "] (" .. cameraID .. ") " .. level .. ": " .. msg)
end

local function onDisconnect(cameraID)
    print("Camera " .. cameraID .. " was disconnected")
    camera = nil
    main()
end

---@param parameters Image.Provider.GigEVision.Ranger3.Parameters
local function manualConfig(parameters)
  local ok = true
  ok = ok and parameters:setReflectanceEnabled(true) -- Turn on Reflectance image
  ok = ok and parameters:setExposureTime(40) -- Set exposure time to 40µs
  ok = ok and parameters:setLaserDetectionThreshold(20) -- Set laser detection threshold to 20 (0-255)
  ok = ok and parameters:setFrameTriggerActivation('OFF') -- Do not use any triggering, to use a photo switch use 'RISING_EDGE'
  ok = ok and parameters:setProfileTriggerSource('TIMER') -- Using Free-running
  ok = ok and parameters:setTimedProfileRate(1000) -- Setting free-running frequence to 1000 Hz
  -- ok = ok and parameters:setProfileTriggerSource('ENCODER') -- Using encoder for triggering profiles
  -- ok = ok and parameters:setEncoderSettings(58, 8, 'DIRECTION_UP') -- Using an encoder with resolution 58 pulses/mm, 8 pulses per profile and mode "DIRECTION_UP"
  ok = ok and parameters:setProfilesPerFrame(2000) -- Number of profiles in a frame, given the encoder settings above image length will be 0.016*8*2000=266 mm

  -- To set parameters that does not have "shortcut functions" you need to use GenICam naming and specify selectors, example below
  ok = ok and parameters:setEnum("PixelFormat", "Coord3D_C16", {"RegionSelector=Scan3dExtraction1","ComponentSelector=Range" }) -- Use 16 bit pixel format, just as an example parameter to set
  ok = ok and parameters:setEnum("SearchMode3D", "GlobalMax", "Scan3dExtractionSelector=Scan3dExtraction1") -- Set search mode to GlobalMax, just as an example parameter to set

  if (ok == false) then
    print("Error: failed to do manual config")
  end

  print("Manual configuration performed!")
end


local function main()
    -- Make sure we have a connected camera object
    connectToRangerOrRuler()

    -- Register event handlers
    local ok = true
    ok = ok and registerEventHandler("OnNewFrame", onNewFrame)
    ok = ok and registerEventHandler("OnLogMessage", onLogMessage)
    ok = ok and registerEventHandler("OnDisconnect", onDisconnect)

    if ok == true then
      local parameters = camera:getParameters()

      -- Setup configuration for the camera if not using already stored parameters
      if setCameraConfig then
        manualConfig(parameters)
      end

      -- Start image acqusition in 3D mode
      camera:start("PROFILE_3D_FRAME")
    end
end

Script.register("Engine.OnStarted", main)

--End of Function and Event Scope-----------------------------------------------
