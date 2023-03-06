--pragma once
if entity_proxy then return end

--locals for expediency
local isfunction = isfunction
local next = next
local rawget = rawget
local rawset = rawset

--module time!
AddCSLuaFile()
module("entity_proxy", package.seeall)

--module fields
Proxies = {} --proxy registry
WaitingProxies = {} --proxies that are waiting for their entity to be received

--local functions
if CLIENT then
	function Create(entity_index, avoid_proxy)
		local first = next(WaitingProxies) == nil
		local proxy = Proxies[entity_index]
		
		--setup expiration up here so it is refreshed when we make duplicate calls
		timer.Create("EntityProxy" .. entity_index, 4, 1, function()
			proxy.IsEntityReceived = true
			
			--destroy the proxy if we don't have the method or the method returns false
			if not proxy.OnEntityProxyExpired or not proxy:OnEntityProxyExpired(entity, entity_index) then Destroy(entity_index) end
		end)
		
		if proxy and proxy:IsEntityProxyAlive() then return avoid_proxy and proxy:GetProxiedEntity() or proxy end
		
		local entity = Entity(entity_index)
		local proxy_detours = {} --stores the detoured functions
		
		--we use _EntityProxyIndex to show debug tools (like PrintTable) that this table is an entity proxy
		proxy = setmetatable({_EntityProxyIndex = entity_index}, {
			__index = function(self, key, ...)
				local value = entity[key]
				
				if isfunction(value) then
					local detoured_function = proxy_detours[key]
					
					if detoured_function then return detoured_function end
					
					local original_function = entity[key]
					detoured_function = function(self, ...) return original_function(entity, ...) end
					proxy_detours[key] = detoured_function
					
					return detoured_function
				end
				
				if value == nil then return rawget(self, key) end
				
				return value
			end,
			
			__name = "EntityProxy",
			
			__newindex = function(self, key, value)
				if rawget(self, "IsEntityReceived") then entity[key] = value
				else rawset(self, key, value) end
			end,
			
			__tostring = ToString,
		})
		
		if entity_index ~= 8191 then
			Proxies[entity_index] = proxy --to prevent duplicates
			proxy.IsEntityReceived = true
			proxy.InvalidEntityProxy = true
		else
			proxy.InvalidEntityProxy = true
			proxy.IsEntityReceived = false
		end
		
		proxy.IsEntityProxy = true
		proxy.IsEntityProxyAlive = IsAlive
		
		function proxy:EntIndex() return entity_index end
		function proxy:GetProxiedEntity() return entity end
		function proxy:GetProxiedEntityDetours() return proxy_detours end
		
		function proxy:SetProxiedEntity(new_entity) --new_entity must be of the same index (for safety)
			entity = new_entity
			entity.IsEntityReceived = true
			
			--move the values from the proxy to the entity
			for key, value in pairs(self) do
				print("moving", key, value)
				
				entity[key] = value
				rawset(self, key, nil)
			end
			
			if entity.OnEntityProxyReceived then proxy:OnEntityProxyReceived(entity) end
		end 
		
		--if the entity is valid, we don't need to create the hook which waits for its creation
		if entity:IsValid() then return avoid_proxy and entity or proxy end
		if first then hook.Add("OnEntityCreated", "EntityProxy", Hook) end --start the watch
		if entity_index ~= 8191 then WaitingProxies[entity_index] = proxy end --add it to the waiting list
		
		return proxy
	end
	
	function Destroy(entity_index) 
		Proxies[entity_index] = nil
		WaitingProxies[entity_index] = nil
		
		timer.Remove("EntityProxy" .. entity_index)
		Unhook()
	end
	
	function Hook(entity)
		--no need for validity check, no one should be networking until after the map has loaded
		local entity_index = entity:EntIndex()
		local proxy = WaitingProxies[entity_index]
		
		if proxy then
			WaitingProxies[entity_index] = nil
			
			--this updates the upvalue and moves the values from the proxy to the entity
			proxy:SetProxiedEntity(entity)
			timer.Remove("EntityProxy" .. entity_index)
			Unhook()
		end
	end
	
	function IsAlive(proxy) return not proxy.IsEntityReceived or proxy:IsValid() end
	
	function Read(avoid_proxy)
		local entity_index = net.ReadUInt(13)
		
		return entity_index and Create(entity_index, avoid_proxy)
	end
	
	function Unhook()
		if next(WaitingProxies) then return end
			
		hook.Remove("OnEntityCreated", "EntityProxy")
	end
	
	function ToString(proxy)
		local text = "[" .. proxy:EntIndex() .. "]"
		
		if proxy:IsValid() then
			if proxy:IsPlayer() then text = "Player [1][" .. proxy:Nick() .. "]"
			else text = text .. "[" .. proxy:GetClass() .. "]" end
		else text = text .. "[NULL Entity]" end
		
		return text .. (received and "[Received]" or "[Not Received]")
	end
else --server doesn't need entity proxies
	function Read()
		local entity_index = net.ReadUInt(13)
		
		return entity_index and Entity(entity_index)
	end
end

--same in both realms
function Write(entity)
	--we use 8191 as the invalid entity index because if you reach this index the server is probably going to crash soon anyways
	--(meaning it will never be reached, and if it is, the issue this would propose is not as big of deal as having an entity with that index)
	--I'm not using 0 so the world entity can be networked since I use it to represent the server in Pyrition and others may do the same
	if entity:IsValid() then net.WriteUInt(entity:EntIndex(), 13)
	else net.WriteUInt(8191, 13) end
end