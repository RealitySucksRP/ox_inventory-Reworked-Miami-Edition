assert(lib.checkDependency('qbx_core', '1.18.1'), 'qbx_core v1.18.1 or higher is required')
assert(lib.checkDependency('qbx_vehicles', '1.2.0'), 'qbx_vehicles v1.2.0 or higher is required')
local Inventory = require 'modules.inventory.server'
local QBX = exports.qbx_core

AddEventHandler('qbx_core:server:playerLoggedOut', server.playerDropped)

AddEventHandler('qbx_core:server:onGroupUpdate', function(source, groupName, groupGrade)
    local inventory = Inventory(source)
    if not inventory then return end
    inventory.player.groups[groupName] = not groupGrade and nil or groupGrade
end)

local function setupPlayer(playerData)
    if not playerData then return end

    playerData.identifier = playerData.citizenid
    playerData.name = ('%s %s'):format(playerData.charinfo.firstname, playerData.charinfo.lastname)
    local inventory = server.setPlayerInventory(playerData)

    if not inventory then return end

    local accounts = Inventory.GetAccountItemCounts(playerData.source)
    if not accounts then return end
    for account in pairs(accounts) do
        local playerAccount = account == 'money' and 'cash' or account
        Inventory.SetItem(playerData.source, account, playerData.money[playerAccount])
    end
end

AddStateBagChangeHandler('loadInventory', nil, function(bagName, _, value)
    if not value then return end
    local plySrc = GetPlayerFromStateBagName(bagName)
    if not plySrc then return end
    local player = QBX:GetPlayer(plySrc)
    if player then setupPlayer(player.PlayerData) end
end)

SetTimeout(500, function()
    local playersData = QBX:GetPlayersData()
    for i = 1, #playersData do setupPlayer(playersData[i]) end
end)

function server.UseItem(source, itemName, data)
    local cb = QBX:CanUseItem(itemName)
    return cb and cb(source, data)
end

---@diagnostic disable-next-line: duplicate-set-field
function server.setPlayerData(player)
    local groups = QBX:GetGroups(player.source)
    return {
        source = player.source,
        name = ('%s %s'):format(player.charinfo.firstname, player.charinfo.lastname),
        groups = groups,
        sex = player.charinfo.gender,
        dateofbirth = player.charinfo.birthdate,
    }
end

---@diagnostic disable-next-line: duplicate-set-field
function server.syncInventory(inv)
    local accounts = Inventory.GetAccountItemCounts(inv)

    if not accounts then return end

    local player = QBX:GetPlayer(inv.id)
    if not player then return end

    player.Functions.SetPlayerData('items', inv.items)

    for account, amount in pairs(accounts) do
        account = account == 'money' and 'cash' or account
        if player.Functions.GetMoney(account) ~= amount then
            player.Functions.SetMoney(account, amount, ('Sync %s with inventory'):format(account))
        end
    end
end

---@diagnostic disable-next-line: duplicate-set-field
function server.hasLicense(inv, license)
    local player = QBX:GetPlayer(inv.id)
    local licences = player and player.PlayerData.metadata.licences
    return licences and licences[license] or false
end

---@diagnostic disable-next-line: duplicate-set-field
function server.buyLicense(inv, license)
    local player = QBX:GetPlayer(inv.id)
    if not player then return end

    local licences = player.PlayerData.metadata.licences or {}

    if licences[license.name] then
        return false, 'already_have'
    elseif Inventory.GetItem(inv, 'money', false, true) < license.price then
        return false, 'can_not_afford'
    end

    if not Inventory.RemoveItem(inv, 'money', license.price) then
        return false, 'can_not_afford'
    end

    licences[license.name] = true
    player.Functions.SetMetaData('licences', licences)

    return true, 'have_purchased'
end

---@diagnostic disable-next-line: duplicate-set-field
function server.isPlayerBoss(playerId, group, grade)
    return QBX:IsGradeBoss(group, grade)
end

---@param playerId number
---@return boolean
---@diagnostic disable-next-line: duplicate-set-field
function server.isPlayerSearchable(playerId)
    local player = QBX:GetPlayer(playerId)
    local metadata = player and player.PlayerData.metadata

    if metadata and (metadata.isdead or metadata.inlaststand or metadata.ishandcuffed) then
        return true
    end

    return Player(playerId).state.canSteal == true
end

---@param entityId number
---@return number?
---@diagnostic disable-next-line: duplicate-set-field
function server.getVehicleClass(entityId)
    if type(entityId) ~= 'number' or entityId <= 0 or not DoesEntityExist(entityId) then return end

    local model = GetEntityModel(entityId)
    if not model or model == 0 then return end

    local ok, class = pcall(QBX.GetVehicleClass, QBX, model)
    if not ok then
        lib.print.warn(('Qbox GetVehicleClass failed for model %s: %s'):format(model, tostring(class)))
        return
    end

    return type(class) == 'number' and class or nil
end

---@param entityId number
---@return number | string
---@diagnostic disable-next-line: duplicate-set-field
function server.getOwnedVehicleId(entityId)
    return Entity(entityId).state.vehicleid or exports.qbx_vehicles:GetVehicleIdByPlate(GetVehicleNumberPlateText(entityId))
end
