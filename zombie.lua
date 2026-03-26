local lp = game:GetService("Players").LocalPlayer
local farming = false
local farm_kb = nil
local circle_angle = 0
local current_hrp = nil
local mouse = lp:GetMouse()

UI.AddTab("Auto Farm", function(tab)
    local farm_sec = tab:Section("Farm", "Left")
    farm_sec:Toggle("farm_on_display", "Farm Enabled", false)
    farm_kb = farm_sec:Keybind("farm_kb", 0x46, "toggle")
    farm_kb:AddToHotkey("Auto Farm", "farm_on_display")
    farm_sec:Toggle("auto_click", "Auto Click", true)
    farm_sec:Spacing()
    farm_sec:SliderInt("tween_speed", "Tween Speed", 100, 2000, 1000)
    farm_sec:SliderInt("stuck_timeout", "Skip Timeout (s)", 1, 10, 3)
    farm_sec:Spacing()
    farm_sec:SliderInt("x_offset", "X Offset", 0, 50, 10)
    farm_sec:SliderInt("y_offset", "Y Offset", 0, 50, 13)
    farm_sec:SliderInt("circle_radius", "Circle Radius", 1, 20, 6)
    farm_sec:SliderInt("circle_step", "Circle Step", 1, 90, 30)

    local info_sec = tab:Section("Info", "Right")
    info_sec:Text("Left-click keybind to rebind")
    info_sec:Text("Right-click to change mode")
    info_sec:Text("X Offset: side distance from zombie")
    info_sec:Text("Y Offset: height above zombie")
    info_sec:Text("Circle Radius: orbit distance")
    info_sec:Text("Circle Step: degrees per move")
    info_sec:Text("Skip Timeout: seconds before next target")
end)

local resolvers = {
    vector3 = function(target) return target end,
    instance = function(target)
        if target:IsA("BasePart") then return target.Position end
    end,
}

local math_util = {
    distance = function(a, b)
        local diff = a - b
        return math.sqrt(diff.X * diff.X + diff.Y * diff.Y + diff.Z * diff.Z)
    end,
    lerp = function(a, b, alpha)
        return Vector3.new(
            a.X + (b.X - a.X) * alpha,
            a.Y + (b.Y - a.Y) * alpha,
            a.Z + (b.Z - a.Z) * alpha
        )
    end,
    easing = {
        linear = function(alpha) return alpha end,
        smoothstep = function(alpha) return alpha * alpha * (3 - 2 * alpha) end,
        ease_in_quad = function(alpha) return alpha * alpha end,
        ease_out_quad = function(alpha) return alpha * (2 - alpha) end,
        ease_in_out_quad = function(alpha)
            if alpha < 0.5 then return 2 * alpha * alpha
            else return -1 + (4 - 2 * alpha) * alpha end
        end,
    }
}

local function tween_to(local_player, target, speed, easing_style)
    local result = {completed = false}
    if not (local_player and target and speed > 0) then
        result.completed = true
        return result
    end
    local char = local_player.Character
    if not char then result.completed = true return result end
    local hrp = char:WaitForChild("HumanoidRootPart")
    local resolve = resolvers[typeof(target):lower()]
    local target_position = resolve and resolve(target)
    if not target_position then result.completed = true return result end
    local start_position = hrp.Position
    local distance = math_util.distance(start_position, target_position)
    local duration = distance / speed
    if duration <= 0 then result.completed = true return result end
    local easing_func = math_util.easing[easing_style] or math_util.easing.linear
    task.spawn(function()
        local elapsed = 0
        local dt = 1 / 240
        while elapsed < duration do
            if not farming then
                result.completed = true
                return
            end
            elapsed = elapsed + dt
            local alpha = math.clamp(elapsed / duration, 0, 1)
            hrp.Position = math_util.lerp(start_position, target_position, easing_func(alpha))
            task.wait(dt)
        end
        hrp.Position = target_position
        hrp.AssemblyLinearVelocity = Vector3.new(0, 0, 0)
        result.completed = true
    end)
    return result
end

local offsets = {
    base_part = { primitive = 0x148 },
    primitive  = { cframe   = 0xC0  },
}

local function distance3(a, b)
    local dx = a.X - b.X
    local dy = a.Y - b.Y
    local dz = a.Z - b.Z
    return math.sqrt(dx*dx + dy*dy + dz*dz)
end

local function project_forward(position, lookVector, distance)
    return Vector3.new(
        position.X + lookVector.X * distance,
        position.Y + lookVector.Y * distance,
        position.Z + lookVector.Z * distance
    )
end

local function read_lookvector(part)
    if not part then return end
    local prim = memory_read("uintptr_t", part.Address + offsets.base_part.primitive)
    if prim == 0 then return end
    local base = prim + offsets.primitive.cframe
    local r02 = memory_read("float", base + 0x08)
    local r12 = memory_read("float", base + 0x14)
    local r22 = memory_read("float", base + 0x20)
    return Vector3.new(-r02, -r12, -r22)
end

local function camera_look_at_target(target)
    local camera = game:GetService("Workspace").CurrentCamera
    if not camera then return end
    if not target then return end
    if not target.Parent then return end
    camera.lookAt(camera.Position, target.Position)
end

local function check_for_equip()
    local char = lp.Character
    if not char then return false end
    for _, v in ipairs(char:GetChildren()) do
        if v.ClassName == "Tool" then
            return true
        end
    end
    return false
end

local function get_sorted_targets()
    local character = lp.Character
    if not character then return {} end
    local hrp = character:FindFirstChild("HumanoidRootPart")
    if not hrp then return {} end
    local workspace    = game:GetService("Workspace")
    local boss_folder  = workspace:FindFirstChild("BossFolder")
    local enemy_folder = workspace:FindFirstChild("enemies")
    local targets = {}
    if boss_folder then
        for _, obj in ipairs(boss_folder:GetChildren()) do
            local obj_hrp = obj:FindFirstChild("HumanoidRootPart")
            if obj_hrp then
                table.insert(targets, {obj = obj, dist = distance3(hrp.Position, obj_hrp.Position)})
            end
        end
    end
    if enemy_folder then
        for _, obj in ipairs(enemy_folder:GetChildren()) do
            local obj_hrp = obj:FindFirstChild("HumanoidRootPart")
            if obj_hrp then
                table.insert(targets, {obj = obj, dist = distance3(hrp.Position, obj_hrp.Position)})
            end
        end
    end
    table.sort(targets, function(a, b) return a.dist < b.dist end)
    return targets
end

-- TOGGLE LOOP
task.spawn(function()
    while true do
        if farm_kb then
            local pressed = farm_kb:IsEnabled()
            if pressed ~= farming then
                farming = pressed
                if farming then
                    notify("Farm started", "Farm", 2)
                else
                    mouse1release()
                    current_hrp = nil
                    notify("Farm stopped", "Farm", 2)
                end
            end
        end
        task.wait()
    end
end)

-- EQUIP LOOP
task.spawn(function()
    while true do
        if farming and not check_for_equip() then
            keypress(0x31)
            task.wait(0.1)
            keyrelease(0x31)
        end
        task.wait(0.1)
    end
end)

-- CAMERA AIM LOOP
task.spawn(function()
    while true do
        if farming and current_hrp then
            camera_look_at_target(current_hrp)
        end
        task.wait(0.01)
    end
end)

-- HOLD CLICK LOOP
task.spawn(function()
    while true do
        if farming and UI.GetValue("auto_click") then
            mouse1press()
        else
            mouse1release()
        end
        task.wait(0.05)
    end
end)

-- MAIN LOOP
task.spawn(function()
    local target_index = 1

    while true do
        if not farming then
            task.wait(0.1)
            continue
        end

        local targets = get_sorted_targets()
        if #targets == 0 then
            current_hrp = nil
            task.wait(1)
            continue
        end

        if target_index > #targets then
            target_index = 1
        end

        local nearest     = targets[target_index].obj
        local nearest_hrp = nearest:FindFirstChild("HumanoidRootPart")
        if not nearest_hrp then task.wait() continue end

        local humanoid = nearest:FindFirstChildWhichIsA("Humanoid")
        if not humanoid or humanoid.Health <= 0 then task.wait() continue end

        current_hrp = nearest_hrp

        local look_vector = read_lookvector(nearest_hrp)
        if not look_vector then task.wait() continue end

        local tp_pos = project_forward(nearest_hrp.Position, look_vector, 5)
        if not tp_pos then task.wait() continue end

        circle_angle = (circle_angle + UI.GetValue("circle_step")) % 360
        local rad    = math.rad(circle_angle)
        local radius = UI.GetValue("circle_radius")
        local orbit  = Vector3.new(
            math.cos(rad) * radius,
            UI.GetValue("y_offset"),
            math.sin(rad) * radius
        )

        local signal = tween_to(
            lp,
            tp_pos + orbit,
            UI.GetValue("tween_speed"),
            "ease_in_quad"
        )

        while not signal.completed do
            task.wait()
        end

        if not farming then task.wait() continue end

        local timer       = 0
        local switched    = false
        local last_health = humanoid.Health

        -- TIMER LOOP
        task.spawn(function()
            while farming and not switched do
                task.wait(1)
                if not farming or switched then break end

                local current_health = humanoid.Health

                if current_health <= 0 then
                    target_index = 1
                    switched = true
                    break
                end

                if current_health < last_health then
                    timer       = 0
                    last_health = current_health
                else
                    timer = timer + 1
                end

                if timer >= UI.GetValue("stuck_timeout") then
                    local next_index = target_index + 1
                    if targets[next_index] then
                        notify("Switching to next target!", "Farm", 2)
                        target_index = next_index
                    else
                        notify("No more targets, resetting!", "Farm", 2)
                        target_index = 1
                    end
                    timer    = 0
                    switched = true
                end
            end
        end)

        -- ORBIT LOOP
        while farming and not switched do
            if not nearest_hrp or not nearest_hrp.Parent then
                target_index = 1
                current_hrp  = nil
                switched = true
                break
            end

            local hum = nearest:FindFirstChildWhichIsA("Humanoid")
            if not hum or hum.Health <= 0 then
                target_index = 1
                current_hrp  = nil
                notify("Zombie died, switching to nearest!", "Farm", 2)
                switched = true
                break
            end

            look_vector = read_lookvector(nearest_hrp)
            if not look_vector then task.wait() continue end

            tp_pos = project_forward(nearest_hrp.Position, look_vector, 5)
            if not tp_pos then task.wait() continue end

            circle_angle = (circle_angle + UI.GetValue("circle_step")) % 360
            local r  = math.rad(circle_angle)
            local rv = UI.GetValue("circle_radius")

            orbit = Vector3.new(
                math.cos(r) * rv,
                UI.GetValue("y_offset"),
                math.sin(r) * rv
            )

            signal = tween_to(
                lp,
                tp_pos + orbit,
                UI.GetValue("tween_speed"),
                "ease_in_quad"
            )

            while not signal.completed and not switched do
                local h = nearest:FindFirstChildWhichIsA("Humanoid")
                if not h or h.Health < 1 then
                    target_index = 1
                    current_hrp  = nil
                    notify("Zombie died, switching to nearest!", "Farm", 2)
                    switched = true
                    break
                end
                task.wait()
            end

            task.wait()
        end

        task.wait()
    end
end)

notify("Auto Farm loaded!", "Farm", 3)