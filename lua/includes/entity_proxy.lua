--pragma once
if entity_proxy then return end

--make this a module
AddCSLuaFile()
module("entity_proxy", package.seeall)

--locals
local default_timeout = CLIENT and 8 --seconds until the proxy expires, false for server
local entity_hook = SERVER and "OnEntityCreated" or "NetworkEntityCreated" --less calls with NetworkEntityCreated
local invalid_entity_index = 8191 --last possible entity index, anything beyond crashes gmod (the game will likely crash if this is index used)

--local function
local function get_entity_index(object)
	--assumptions made here:
	--	Entity = typical entity, get the index or use invalid_entity_index to represent a NULL entity
	--	number = entity index
	--	table = EntityProxy 
	if object:IsValid() or istable(object) then return object:EntIndex()
	elseif isentity(object) then return invalid_entity_index end
	
	return object
end

--module fields
Proxies = {}
WaitingProxies = {}

--module functions
function Clear(namespace) for entity_index in pairs(Proxies[namespace]) do DestroyInternal(namespace, entity_index) end end
function Create(namespace, entity_index, timeout) return CreateInternal(namespace, get_entity_index(entity_index), timeout) end

function CreateInternal(namespace, entity_index, timeout)
	local deleting --client side only
	local deleting_null_safety --client side only
	local entity = Entity(entity_index)
	local hook_name = "EntityProxy" .. namespace
	local new_index
	local null_safety = {}
	local on_entity_remove
	local proxies = Proxies[namespace]
	local proxy
	local proxy_detours = {}
	local reference_count = 0
	local timeout = timeout
	local timer_name = hook_name .. entity_index
	local valid = entity:IsValid() --reduce function calls (mainly for __newindex metamethod)
	local waiting_proxies = WaitingProxies[namespace]
	local waiting_proxies_empty = next(waiting_proxies) == nil
	
	local function check_reference_count()
		if reference_count <= 0 then
			DestroyInternal(namespace, entity_index)
			
			return true
		end
		
		return false
	end
	
	local function timeout_callback()
		rawset(proxy, "EntityProxyTimeout", CurTime())
		
		--if the user returns true in the OnEntityProxyTimeout callback, destroy the proxy
		--they can set this to true instead of a function if they don't want
		if proxy.OnEntityProxyTimeout and (proxy.OnEntityProxyTimeout == true or proxy:OnEntityProxyTimeout()) then
			--this behavior isn't always desired, as we may want to purposefully hold a reference to an invalid entity
			DestroyInternal(namespace, entity_index)
		end
	end
	
	--since timeout can be false, we can't do `timeout or default_timeout`
	if timeout == nil then timeout = default_timeout end
	
	--timeout timer
	if timeout ~= false and not valid then timer.Create(timer_name, timeout or default_timeout, 1, timeout_callback)
	else timer.Remove(timer_name) end
	
	if SERVER then
		function new_index(_self, key, value)
			if valid then
				entity[key] = value
				null_safety[key] = true
			else null_safety[key] = value end
		end
		
		function on_entity_remove(self)
			valid = false
			
			--copy the original values over to null_safety before the entity is removed!
			for key in pairs(null_safety) do null_safety[key] = self[key] end
			for key in pairs(proxy_detours) do proxy_detours[key] = nil end --clear the detours!
			
			if proxy.OnProxiedEntityRemove and (proxy.OnProxiedEntityRemove == true or proxy:OnProxiedEntityRemove()) then
				--this behavior isn't always desired, as we may want to purposefully hold a reference to an invalid entity
				DestroyInternal(namespace, entity_index)
			end
		end
	else
		deleting = false
		deleting_null_safety = {}
		
		function new_index(_self, key, value)
			if valid then
				entity[key] = value
				null_safety[key] = true
				
				if deleting then deleting_null_safety[key] = value end
			else null_safety[key] = value end
		end
		
		function on_entity_remove(self)
			--this is more complex on client, as a full update can trigger the callback
			if deleting then return end --duplicate call! let the existing timer handle this
			
			deleting = true
			
			--we don't modify the safe table until we are sure the entity was deleted
			for key in pairs(null_safety) do deleting_null_safety[key] = self[key] end
			
			--HACK: awaiting a fix for false OnRemove calls since 1922
			timer.Simple(0, function()
				deleting = false
				
				if self:IsValid() then
					--it was a full update, save some memory and don't move the values
					for key in pairs(deleting_null_safety) do deleting_null_safety[key] = nil end
				else
					--the entity was actually removed!
					for key, value in pairs(deleting_null_safety) do
						deleting_null_safety[key] = nil --free the memory
						null_safety[key] = value --move the values to a usable table
					end
					
					--clear the detours!
					for key in pairs(proxy_detours) do proxy_detours[key] = nil end
					
					if proxy.OnProxiedEntityRemove and (proxy.OnProxiedEntityRemove == true or proxy:OnProxiedEntityRemove()) then
						--this behavior isn't always desired, as we may want to purposefully hold a reference to an invalid entity
						DestroyInternal(namespace, entity_index)
					end
				end
			end)
		end
	end
	
	--setup the removal callback
	if valid then entity:CallOnRemove(hook_name, on_entity_remove) end
	
	proxy = setmetatable({
		ClearProxiedEntityDetours = function() for key in pairs(proxy_detours) do proxy_detours[key] = nil end end,
		
		DecrementEntityProxyReferenceCount = function(_self, increment)
			reference_count = reference_count - (increment or 1)
			
			return check_reference_count()
		end,
		
		EntIndex = function() return entity_index end, --makes EntIndex always work - even when the entity is invalid!
		GetEntityProxyDetours = function() return proxy_detours end,
		GetEntityProxyNamespace = function() return namespace end,
		GetEntityProxyReferenceCount = function() return reference_count end,
		GetProxiedEntity = function() return entity end,
		IncrementEntityProxyReferenceCount = function(_self, increment) reference_count = reference_count + (increment or 1) end,
		IsEntityProxyAlive = function() return proxies[entity_index] == proxy end,
		RefreshEntityProxyTimer = function() timer.Create(timer_name, timeout or default_timeout, 1, timeout_callback) end,
		
		SetEntityProxyReferenceCount = function(_self, count)
			reference_count = count
			
			return check_reference_count()
		end,
		
		SetProxiedEntity = function(_self, new_entity)
			entity = new_entity
			
			if entity:IsValid() then
				valid = true
				
				--setup the removal callback
				entity:CallOnRemove("EntityProxy" .. namespace, on_entity_remove)
				
				for key, value in pairs(null_safety) do
					entity[key] = value
					null_safety[key] = true --smol - not an address (needs validation)
				end
			end
		end
	}, {
		__index = function(self, key)
			local proxy_value = rawget(self, key)
			
			--information the proxy holds always has priority so we can access essential methods
			if proxy_value ~= nil then return proxy_value end
			
			local entity_value = entity[key]
			
			--make sure entity methods use detours instead
			if isfunction(entity_value) then
				local detoured_function = proxy_detours[key]
				
				if detoured_function then return detoured_function end
				
				detoured_function = function(first, ...)
					--if the function was a method and we tried to call it on the proxy, call it on the entity instead
					if first == self then return entity_value(entity, ...) end
					
					return entity_value(first, ...)
				end
				
				proxy_detours[key] = detoured_function
				
				return detoured_function
			end
			
			if entity_value == nil then return null_safety[key] end
			
			return entity_value
		end,
		
		__name = "EntityProxy",
		__newindex = new_index,
		__tostring = ToString
	})
	
	proxies[entity_index] = proxy
	
	--don't wait for the reception if the entity is already valid or was sent invalid
	if valid or entity_index == invalid_entity_index then return proxy end
	
	waiting_proxies[entity_index] = proxy
	
	--create the hook if not already done
	if waiting_proxies_empty then
		hook.Add(entity_hook, hook_name, function(created_entity)
			local created_entity_index = created_entity:EntIndex()
			local waiting_proxy = waiting_proxies[created_entity_index]
			
			if waiting_proxy then
				waiting_proxies[created_entity_index] = nil
				
				rawset(waiting_proxy, "ProxyReceivedEntity", true)
				timer.Remove(timer_name)
				waiting_proxy:SetProxiedEntity(created_entity)
				
				if waiting_proxy.OnEntityProxyReceived then waiting_proxy:OnEntityProxyReceived(created_entity) end
				if next(waiting_proxies) then return end --dont remove the hook until the queue is empty
				
				hook.Remove(entity_hook, hook_name)
			end
		end)
	end
	
	return proxy
end

function Destroy(namespace, entity_index) DestroyInternal(namespace, get_entity_index(entity_index)) end

function DestroyInternal(namespace, entity_index)
	local proxies = Proxies[namespace]
	local proxy = proxies[entity_index]
	
	if proxy then
		if proxy.OnEntityProxyDestroyed then proxy:OnEntityProxyDestroyed() end
		
		local waiting_proxies = WaitingProxies[namespace]
		
		proxies[entity_index] = nil
		waiting_proxies[entity_index] = nil
		
		--timeout timer
		timer.Remove("EntityProxy" .. namespace .. entity_index)
		
		--don't remove the hook since we are waiting on more
		if next(waiting_proxies) then return end
		
		hook.Remove(entity_hook, "EntityProxy" .. namespace)
	end
end

function Get(namespace, entity_index, timeout)
	entity_index = get_entity_index(entity_index)
	local proxies = Proxies[namespace]
	local proxy = proxies[entity_index]
	
	if proxy then proxy:RefreshEntityProxyTimer()
	else proxy = CreateInternal(namespace, entity_index, timeout) end
	
	return proxy
end

function GetExisting(namespace, entity_index) return Proxies[namespace][get_entity_index(entity_index)] end
function Read(namespace, timeout) return Get(namespace, net.ReadUInt(13), timeout) end

function Register(namespace)
	if Proxies[namespace] then return end
	
	Proxies[namespace] = {}
	WaitingProxies[namespace] = {}
end

function ToString(proxy)
	local entity_index = proxy:EntIndex()
	local text = "[" .. entity_index .. "]"
	
	if proxy:IsValid() then
		if proxy:IsPlayer() then text = "Player [" .. entity_index .. "][" .. proxy:Nick() .. "]"
		else text = text .. "[" .. proxy:GetClass() .. "]" end
	else text = text .. "[NULL Entity]" end
	
	local status = proxy.ProxyReceivedEntity
	
	if proxy.ProxyReceivedEntity then status = Proxies[namespace][entity_id] and "[Received]" or "[Destroyed after reception]"
	else
		local namespace = proxy:GetEntityProxyNamespace()
		local timed_out_at = proxy.EntityProxyTimeout
		local waiting_proxy = WaitingProxies[namespace][entity_index]
		
		if waiting_proxy == proxy then status = "[Waiting]"
		elseif timed_out_at then status = "[Timed out " .. math.Round(CurTime() .. timed_out_at, 2) .. " seconds ago]"
		elseif Proxies[namespace][entity_id] then status = "[Unreceived]"
		else status = "[Destroyed]" end
	end
	
	return text .. status
end

function Write(entity_index) net.WriteUInt(get_entity_index(entity_index)) end