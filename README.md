# Networking Entity Proxy Module
Magical code that makes networking entities (more) reliable. [Workshop link](https://steamcommunity.com/sharedfiles/filedetails/?id=2943025031).  
Both realms can create proxies, so you can just to hold a reliable reference to an invalid entity.
Anything marked with **INTERNAL** shouldn't be used unless you know what you're doing.

# Why would you need this? To:
 *  Reliably network entities by fixing race conditions between entity networking and net messages
 *  Maintain information about an entity after it has been removed
 *  Hold references to entities that will never exist (eg. server side entities on client)

# Module
The module name is `entity_proxy` and for the most part, you should only need to use `Read`, `Write`, and `Destroy`. The original aim of this module was to easily fix existing projects that network entities over net messages improperly. This aim is still valid, but this module can also be used to better manage invalid entities.

# Module Fields
Safe to read, not so safe to write.
|     Field      | Type    | Description                                                                         |
| :------------: | ------- | ----------------------------------------------------------------------------------- |
|    Proxies     | `table` | **INTERNAL** Contains all the namespaces' tables of live proxies                                 |
| WaitingProxies | `table` | **INTERNAL** Contains all the namespaces' tables of proxies waiting for an entity to be received |

# Module Functions
It is safe to assume that `any:entity_index` can be a `number`, `Entity`, or `EntityProxy`.  
The default timeout is `8` on the client, and `false` on the server meaning the server won't wait for the entity to be created.
|    Function     | Parameters                                                        | Returns       | Description                                                                   |
| :-------------: | ----------------------------------------------------------------- | ------------- | ----------------------------------------------------------------------------- |
|      Clear      | `string:namespace`                                                |               | Calls `DestroyInternal` on all proxies in the namespace                       |
|     Create      | `string:namespace` `any:entity_index` `number/boolean:timeout`    | `EntityProxy` | Calls `CreateInternal` after converting `entity_index`to a number             |
| CreateInternal  | `string:namespace` `number:entity_index` `number/boolean:timeout` | `EntityProxy` | **INTERNAL** Creates and register a proxy (timeout will use default if `nil`) |
|     Destroy     | `string:namespace` `any:entity_index`                             |               | Calls `DestroyInternal` after converting `entity_index`to a number            |
| DestroyInternal | `string:namespace` `number:entity_index`                          |               | **INTERNAL** Destroys the entity proxy dropping it from the `Proxies` table   |
|       Get       | `string:namespace` `any:entity_index` `number/boolean:timeout`    | `EntityProxy` | Returns an existing proxy or creates one                                      |
|   GetExisting   | `string:namespace` `any:entity_index`                             | `EntityProxy` | Returns an existing proxy or `nil` if it doesn't exist                        |
|      Read       | `string:namespace` `number/boolean:timeout`                       | `EntityProxy` | Reads 13 bits and calls `Get`                                                 |
|    Register     | `string:namespace`                                                |               | Creates the tables required to use this module with the given namespace       |
|    ToString     | `EntityProxy`                                                     | `string`      | Creates a string with useful debug information about the proxy                |
|      Write      | `any:entity_index`                                                |               | Writes a 13-bit unsigned integer after converting `entity_index` to a number  |


# Example
```lua
--don't use require as clients can exploit that to load binary modules instead
--it is safe to include the module across multiple files as it only loads once
include("includes/entity_proxy.lua")
util.AddNetworkString("SomeNetMessage")

if SERVER then
	--grabbing a random entity for this example
	local entities = ents.GetAll()
	local some_entity = entities[math.random(#entities)]
	
	net.Start("SomeNetMessage")
	entity_proxy.Write(some_entity) --use this instead of net.WriteEntity
	net.Broadcast()
else --the CLIENT
	net.Receive("SomeNetMessage", function()
		local entity_proxy = entity_proxy.Read() --use this instead of net.ReadEntity
		
		print("received an entity proxy", entity_proxy)
		
		if entity_proxy:IsValid() then
			print("since the entity was valid when it was received, we can immediately use it!")
			print(entity_proxy:EntIndex(), entity_proxy:GetPos(), entity_proxy:GetClass())
		else
			print("the entity was not valid immediately, thus the module will wait for it to be created")
			
			--if you want to do something immediately after the entity is created, you can use the OnEntityProxyReceived method
			function entity_proxy:OnEntityProxyReceived(entity)
				--please note that this will most likely not be called in this example
				--this is more useful for entities created on the server at a similar time to when the net message is sent
				--but in this example we are just grabbing random entities, which are most likely server side entities if they are not valid on the client
				print("the entity was created, it is now useful!")
				print("the proxy is `self`", self)
				print("and the unproxied Entity is `entity`", entity)
			end
			
			function entity_proxy:OnEntityProxyTimeout()
				--if you don't want the entity to timeout,
				print("the entity was not created in time, so the proxy timed out!", self)
			end
		end
	end)
end
```

# EntityProxy
For the most part an proxy like an entity, but will become valid once the entity is created instead of staying invalid. Comes with a few useful methods and metamethods. Internally, they are tables 

## Fields
No need to set these, they are automatically set for you. Reading from them is safe.
|        Field        | Type             | Description                                                               |
| :-----------------: | ---------------- | ------------------------------------------------------------------------- |
| EntityProxyTimeout  | `number:curtime` | Set to the curtime that the proxy timed out at (`nil` otherwise)          |
| ProxyReceivedEntity | `boolean`        | Set to `true` if the entity was received after creation (`nil` otherwise) |
|       __name        | `string`         | Always set to `EntityProxy`                                               |

## Methods
|               Method               | Parameters    | Returns             | Description                                                                                                |
| :--------------------------------: | ------------- | ------------------- | ---------------------------------------------------------------------------------------------------------- |
|     ClearProxiedEntityDetours      |               |                     | Removed all existing entity method detours                                                                 |
| DecrementEntityProxyReferenceCount | `number`      | `boolean:destroyed` | Subtract the `reference_count` local by `number` (defaults to 1) and calls `DestroyInternal` at 0 or below |
|              EntIndex              |               | `number`            | Sames as `Entity:EntIndex` but also works invalid entities                                                 |
|       GetEntityProxyDetours        |               | `table`             | Returns the `proxy_detours` local table used by the proxy                                                  |
|      GetEntityProxyNamespace       |               | `string`            | Returns the namespace the entity proxy belongs to (the one it was created with)                            |
|    GetEntityProxyReferenceCount    |               | `number`            | Gets the `reference_count` local                                                                           |
|          GetProxiedEntity          |               | `Entity`            | Self explanatory                                                                                           |
| IncrementEntityProxyReferenceCount | `number`      |                     | Add the `reference_count` local by `number` (defaults to 1)                                                |
|         IsEntityProxyAlive         |               | `boolean`           | Returns `true` if the proxy is still registered under the namespace (`false` otherwise)                    |
|       OnEntityProxyDestroyed       |               |                     | Called when the proxy is destroyed (with `DestroyInternal`)                                                |
|       OnEntityProxyReceived        | `entity`      |                     | Called when an entity with the matching index has been created (called after `SetProxiedEntity`)           |
|        OnEntityProxyTimeout        |               | `boolean`           | Set to `true` or return `true` to call `DestroyInternal`                                                   |
|       OnProxiedEntityRemove        |               | `boolean`           | Set to `true` or return `true` to call `DestroyInternal`, called when the entity is removed                |
|      RefreshEntityProxyTimer       |               |                     | Restarts the timeout timer                                                                                 |
|    SetEntityProxyReferenceCount    | `number`      | `boolean:destroyed` | Set the `reference_count` local to `number` and call `DestroyInternal` at 0 or below                       |
|          SetProxiedEntity          | `entity`      |                     | **INTERNAL** Sets the entity upvalue, moves null safety values, and sets up removal callback               |
|              __index               | `key`         | `any`               | **INTERNAL**                                                                                               |
|             __newindex             | `key` `value` |                     | **INTERNAL** Sets the value on the entity if it's valid, otherwise caches them until received              |
|             __tostring             |               | `string`            | Formats useful data about the entity proxy into a string for debugging                                     |
