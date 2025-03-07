// Gingerbeard @ January 16th, 2025

#define SERVER_ONLY

#include "PathingNodesCommon.as";

void onInit(CRules@ this)
{
	onRestart(this);
}

void onReload(CRules@ this)
{
	onRestart(this);
}

void onRestart(CRules@ this)
{
	HighLevelNode@[][] queued_node_updates;
	this.set("queued_node_updates", @queued_node_updates);

	InitializeNodeMap(this);
	
	CMap@ map = getMap();
	if (!map.hasScript(getCurrentScriptName()))
	{
		map.AddScript(getCurrentScriptName());
	}
}

void onSetTile(CMap@ map, u32 index, TileType newtile, TileType oldtile)
{
	onMapTileCollapse(map, index);
}

void onMapFloodLayerUpdate(CMap@ map, s32 index) //STAGING ONLY as of march 6th, 2025
{
	onMapTileCollapse(map, index);
}

bool onMapTileCollapse(CMap@ map, u32 index)
{
	dictionary@ nodeMap;
	CRules@ rules = getRules();
	if (!rules.get("node_map", @nodeMap)) return true;

	Vec2f position = map.getTileWorldPosition(index);
	rules.push("queued_node_updates", getNodesInRadius(position, node_distance * 2.25f, nodeMap));
	
	return true;
}

void onTick(CRules@ this)
{
	HighLevelNode@[][]@ queued_node_updates;
	if (!this.get("queued_node_updates", @queued_node_updates)) return;

	if (queued_node_updates.length == 0) return;
	
	const int index = queued_node_updates.length - 1;
	HighLevelNode@[] node_update = queued_node_updates[index];

	CMap@ map = getMap();

	for (int i = 0; i < node_update.length; i++)
	{
		UpdateNodePosition(node_update[i], map);
	}

	for (int i = 0; i < node_update.length; i++)
	{
		UpdateNodeConnections(node_update[i], map);
	}

	queued_node_updates.erase(index);
}

void InitializeNodeMap(CRules@ this)
{
	dictionary nodeMap;
	this.set("node_map", @nodeMap);

	CMap@ map = getMap();
	Vec2f dim = map.getMapDimensions();

	Vec2f[] node_directions = { Vec2f(-node_distance, 0), Vec2f(0, -node_distance) };

	HighLevelNode@[] node_update;
	for (u32 x = node_distance; x < dim.x; x += node_distance)
	{
		for (u32 y = node_distance; y < dim.y; y += node_distance)
		{
			Vec2f nodepos = Vec2f(x, y);
			HighLevelNode@ node = HighLevelNode(nodepos);

			for (u32 i = 0; i < node_directions.length; i++)
			{
				Vec2f neighborPos = nodepos + node_directions[i];

				HighLevelNode@ neighborNode;
				if (nodeMap.get(neighborPos.toString(), @neighborNode))
				{
					// Connect the new node to the neighbor and vice versa
					node.connections.push_back(@neighborNode);
					neighborNode.connections.push_back(@node);
					
					node.original_connections.push_back(@neighborNode);
					neighborNode.original_connections.push_back(@node);
				}
			}

			nodeMap.set(node.position.toString(), @node);
			node_update.push_back(node);
		}
	}
	this.push("queued_node_updates", node_update);
}

void UpdateNodeConnections(HighLevelNode@ node, CMap@ map)
{
	node.connections = node.original_connections;

	for (int i = node.connections.length - 1; i >= 0; i--)
	{
		HighLevelNode@ neighbor = node.connections[i];

		if (neighbor.hasFlag(Path::DISABLED) || !canNodesConnect(node.position, neighbor.position, map))
		{
			node.connections.erase(i);

			for (int n = neighbor.connections.length - 1; n >= 0; n--)
			{
				if (neighbor.connections[n].original_position != node.original_position) continue;

				neighbor.connections.erase(n);
			}
		}
	}
}

void UpdateNodePosition(HighLevelNode@ node, CMap@ map)
{
	node.position = node.original_position;
	node.flags = 0;

	const bool walkable = isWalkable(node.original_position, map);
	if (walkable && isSupported(node.original_position, map))
	{
		node.flags |= Path::GROUND;
		return;
	}
	
	Vec2f dim = map.getMapDimensions();

	// Look for the nearest walkable tile in a small radius
	const u8 searchRadius = 3;
	Vec2f closestPos = node.original_position;
	f32 closestDistance = 999999.0f;

	for (int y = -searchRadius; y <= searchRadius; y++)
	{
		for (int x = -searchRadius; x <= searchRadius; x++)
		{
			Vec2f neighborPos = node.original_position + Vec2f(x * tilesize, y * tilesize);

			if (isWalkable(neighborPos, map) && isSupported(neighborPos, map) && isInMap(neighborPos, dim))
			{
				const f32 distance = (neighborPos - node.original_position).LengthSquared();
				if (distance < closestDistance)
				{
					closestDistance = distance;
					closestPos = neighborPos;
				}
			}
		}
	}

	// If no walkable tile is found, mark the node as disabled
	if (closestDistance == 999999.0f)
	{
		if (walkable)
			node.flags |= Path::AERIAL;
		else
			node.flags = Path::DISABLED;
		return;
	}

	node.position = closestPos;
	node.flags |= Path::GROUND;
}

bool isWalkable(Vec2f&in tilePos, CMap@ map)
{
	for (u8 i = 0; i < 4; i++)
	{
		if (map.isTileSolid(tilePos + walkableDirections[i])) return false;
	}
	return true;
}

bool isSupported(Vec2f&in tilePos, CMap@ map)
{
	for (u8 i = 0; i < 4; i++)
	{
		// Are we adjacent to solid tiles
		if (map.isTileSolid(tilePos + cardinalDirections[i] * 1.5f)) return true;
	}

	if (map.isInWater(tilePos + Vec2f(0, tilesize))) return true;

	CBlob@[] blobs;
	Vec2f tile(halfsize, halfsize);
	if (map.getBlobsInBox(tilePos - tile, tilePos + tile, @blobs))
	{
		for (int i = 0; i < blobs.length; i++)
		{
			CBlob@ b = blobs[i];
			if (b.getShape().getVars().isladder) return true;
			
			//if (b.isPlatform()) return true;
		}
	}

	return false;
}

bool isInMap(Vec2f&in tilePos, Vec2f&in dim)
{
	return tilePos.x > 0 && tilePos.y > 0 && tilePos.x < dim.x && tilePos.y < dim.y;
}

bool canNodesConnect(Vec2f start, Vec2f end, CMap@ map)
{
	if ((start - end).Length() > node_distance * 1.7f) return false;

	if (!isWalkable(start, map)) return false;

	Vec2f minBound = Vec2f(Maths::Min(start.x, end.x) - tilesize * 2, Maths::Min(start.y, end.y) - tilesize * 2);
	Vec2f maxBound = Vec2f(Maths::Max(start.x, end.x) + tilesize * 2, Maths::Max(start.y, end.y) + tilesize * 2);

	Vec2f[] openList;
	dictionary closedList;

	openList.push_back(start);

	while (!openList.isEmpty())
	{
		Vec2f current = openList[0];
		openList.removeAt(0);

		if (current == end) return true;

		const string nodeKey = current.toString();
		if (closedList.exists(nodeKey)) continue;

		closedList.set(nodeKey, true);

		for (u8 i = 0; i < 4; i++)
		{
			Vec2f neighbor = current + cardinalDirections[i];

			if (neighbor.x >= minBound.x && neighbor.y >= minBound.y &&
				neighbor.x <= maxBound.x && neighbor.y <= maxBound.y &&
				!closedList.exists(neighbor.toString()) && isWalkable(neighbor, map))
			{
				openList.push_back(neighbor);
			}
		}
	}

	return false;
}

void onRender(CRules@ this)
{
	if ((!render_paths && g_debug == 0) || g_debug == 5) return;
	
	dictionary@ nodeMap;
	if (!this.get("node_map", @nodeMap)) return;

	SColor nodeColor(255, 0, 255, 0);
	SColor connectionColor(255, 255, 0, 0);
	SColor airColor(255, 160, 160, 160);
	Driver@ driver = getDriver();
	Vec2f center = driver.getScreenCenterPos();
	Vec2f screen_dim = driver.getScreenDimensions();
	
	const u8 render_blacklist = Path::DISABLED | Path::AERIAL; //stops these types of path from rendering

	const string[]@ node_keys = nodeMap.getKeys();
	for (u32 i = 0; i < node_keys.length; i++)
	{
		HighLevelNode@ node;
		if (!nodeMap.get(node_keys[i], @node) || node.hasFlag(render_blacklist)) continue;

		Vec2f pos = driver.getScreenPosFromWorldPos(node.position);
		if ((pos - center).Length() > screen_dim.x) continue;

		GUI::DrawCircle(pos, 4.0f, node.hasFlag(Path::AERIAL) ? airColor : nodeColor);

		for (u32 j = 0; j < node.connections.length; j++)
		{
			HighLevelNode@ neighbor = node.connections[j];
			if (neighbor is null || neighbor.hasFlag(render_blacklist)) continue;
			
			Vec2f neighborpos = driver.getScreenPosFromWorldPos(neighbor.position);
			GUI::DrawLine2D(pos, neighborpos, neighbor.hasFlag(Path::AERIAL) || node.hasFlag(Path::AERIAL) ? airColor :connectionColor);
		}
	}
}
