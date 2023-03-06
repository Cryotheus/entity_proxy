# Networking Entity Proxy Module
Magical code that makes networking entities (more) reliable.  
Only clients create proxies as the server should never be waiting for an entity to be created (it's the realm creating them after all).  
This module is shared, but most of the functionality is in client realm.  
Anything marked with **INTERNAL** shouldn't be used unless you know what you're doing.

## Cool, but what does this fix?
Race conditions? Sure, lets say that.  
Occasionally, you may want to send an entity to the client through a net message but you can't be sure if the client has received the entity yet (usually happens when the entity is created the same tick the net message is sent). This fixes that. Use `entity_proxy.Read` and `entity_proxy.Write` to send entities over net messages and you'll be able to receive them even if they haven't been created yet. When the entity is created on the client, it will be automatically updated with the real entity. In addition, this lets you have multiple invalid entities as keys in a table. For the most part, the proxy can be treated just like a normal entity. Be aware however, in truth it's just a table with meta methods.  

Bullet points of things you can do with this in case you need a *TL;DR*:
 *  Send entities over net messages before the entity is created on client.
 *  Use multiple invalid entities as keys in tables.
 *  Hold a reference to entities that will never exist on the client.

## EntityProxy
A table with some meta methods to make entity networking easier.  

### Methods
|          Method         | Parameters                     | Returns                | Description                                                        |
| :---------------------: | ------------------------------ | ---------------------- | ------------------------------------------------------------------ |
|         EntIndex        |                                | `number:entity_index`  | Same as `Entity:EntIndex()` but works even with an invalid entity. |
|     GetProxiedEntity    |                                | `entity`               | Returns the proxied entity, even if it's invalid.                  |
| GetProxiedEntityDetours |                                | `table:detours`        | **INTERNAL** Returns the detours table. All values are functions.  |
|    IsEntityProxyAlive   |                                | `boolean`              | Same as `entity_proxy.IsAlive(proxy)` where proxy is `self`.       |
|  OnEntityProxyExpired   | `entity` `number:entity_index` | `boolean:dont_destroy` | Called when the entity was not received.                           |
|  OnEntityProxyReceived  | `entity`                       |                        | Called when the entity is received.                                |
|     SetProxiedEntity    | `entity:new_entity`            |                        | **INTERNAL** Sets the proxied entity.                              |

### Fields
Mostly internal. Safe to access, but modification is not recommended.
|        Field       |    Type   | Description                                                         |
| :----------------: | :-------: | ------------------------------------------------------------------- |
| InvalidEntityProxy | `boolean` | `true` if the entity received was of index 8191 (invalid entity).   |
|    IsEntityProxy   | `boolean` | Always `true`.                                                      |
|  IsEntityReceived  | `boolean` | `true` if the entity has been received after the proxy was created. |

## Module Functions
The modules is `entity_proxy` and can be loaded with `include("includes/entity.lua")` placed anywhere before usage of the module.  
You can use the functions like `entity_proxy.Write(some_entity)`. The module is only loaded once, so you can `include` it in multiple files without worrying the module being loaded multiple times. Don't use `require` as malicious clients can use it to load malicious binary modules on their realm (stuff like aimbot).  
The server only has access to `Read` and `Write`, all other functions are available in client realm only.
| Function | Parameters                                  | Returns       | Description                                                                        |
| :------: | ------------------------------------------- | ------------- | ---------------------------------------------------------------------------------- |
|  Create  | `number:entity_index` `boolean:avoid_proxy` | `table:proxy` | **INTERNAL** Creates an entity proxy and registers it for receiving.               |
|  Destroy | `number:entity_index`                       |               | Stops waiting for the entity to be created, and unregisters it.                    |
|   Hook   | `Entity:entity`                             |               | **INTERNAL** The function used in the `OnEntityCreated` hook.                      |
|  IsAlive | `table:proxy`                               | `boolean`     | Checks if the proxy's entity is valid or has yet to be received.                   |
|   Read   | `boolean:avoid_proxy`                       | `table:proxy` | `avoid_proxy` will return an `Entity` instead of its proxy if it's a valid entity. |
|  Unhook  |                                             |               | **INTERNAL** Attempts to remove the `OnEntityCreated` hook.                        |
|   Write  | `entity`                                    |               | Writes a 13-bit unsigned integer of the entity's index.                            |

## Fields
You shouldn't have to touch there, but they're here if you need them.  
These are available on both the client and the server realms.
|      Field     |   Type  | Description                                                                                              |
| :------------: | :-----: | -------------------------------------------------------------------------------------------------------- |
| Proxies        | `table` | A table of all the proxies where the key is the entity index.                                            |
| WaitingProxies | `table` | A table of all the proxies that are waiting for their entity to be created. The entity index is the key. |
