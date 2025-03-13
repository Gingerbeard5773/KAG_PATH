// Knight brain

#define SERVER_ONLY

#include "BrainCommon.as"
#include "BrainPathing.as"

// Gingerbeard @ March 6th, 2025

// here is an example of a pathing implementation for a bot
// since i didnt spend a lot of time, these bots are still pretty dumb, but they are able to path around
// parkour has not been implemented and so they get stuck in holes etc


void onInit(CBrain@ this)
{
	InitBrain(this);
	
	this.server_SetActive(true);

	CBlob@ blob = this.getBlob();
	PathHandler handler(blob.getTeamNum(), Path::GROUND);
	blob.set("path_handler", @handler);
}

void onTick(CBrain@ this)
{

	CBlob@ blob = this.getBlob();

	PathHandler@ handler;
	if (!blob.get("path_handler", @handler)) return;
	if (blob.getPlayer() !is null)
	{
		handler.EndPath();
		this.server_SetActive(false);
		return;
	}

	handler.Tick(blob.getPosition());

	SetSuggestedKeys(blob);
	SetSuggestedFacing(blob);

	CBlob@ target = this.getTarget();
	if (target is null || XORRandom(20) == 0)
	{
		@target = getNewTarget(blob);
		this.SetTarget(target);
	}

	u8 strategy = blob.get_u8("strategy");

	if (target !is null)
	{
		f32 distance;
		const bool visibleTarget = isVisible(blob, target, distance);
		if (visibleTarget && distance < 50.0f)
		{
			strategy = Strategy::attacking;
		}

		if (strategy == Strategy::idle)
		{
			strategy = Strategy::chasing;
		}
		else if (strategy == Strategy::chasing && (getGameTime() + blob.getNetworkID() * 10) % 20 == 0)
		{
			SetPath(blob, target.getPosition());
		}
		else if (strategy == Strategy::attacking)
		{
			if (!visibleTarget || distance > 120.0f)
			{
				strategy = Strategy::chasing;
			}
		}

		/*if (strategy == Strategy::chasing)
		{
			DefaultChaseBlob(blob, target);
		}*/
		if (strategy == Strategy::attacking)
		{
			EndPath(blob);
			AttackBlob(blob, target);
		}

		// lose target if its killed (with random cooldown)

		if (LoseTarget(this, target))
		{
			EndPath(blob);
			strategy = Strategy::idle;
		}

		blob.set_u8("strategy", strategy);
	}
	else if (strategy == Strategy::idle)
	{
		// wander around the map
		if (handler.destination == Vec2f_zero)
		{
			CMap@ map = getMap();
			Vec2f dim = map.getMapDimensions();
			SetPath(blob, Vec2f(XORRandom(dim.x), XORRandom(dim.y)));
		}
		/*else if ((getGameTime() + blob.getNetworkID() * 10) % 30 == 0)
		{
			handler.Repath(blob.getPosition());
		}*/
	}

	if (handler.destination == Vec2f_zero)
	{
		FloatInWater(blob);
	}
}


void AttackBlob(CBlob@ blob, CBlob @target)
{
	Vec2f mypos = blob.getPosition();
	Vec2f targetPos = target.getPosition();
	Vec2f targetVector = targetPos - mypos;
	f32 targetDistance = targetVector.Length();
	const s32 difficulty = blob.get_s32("difficulty");

	if (targetDistance > blob.getRadius() + 15.0f)
	{
		Chase(blob, target);
	}

	JumpOverObstacles(blob);

	// aim always at enemy
	blob.setAimPos(targetPos);

	const u32 gametime = getGameTime();

	bool shieldTime = gametime - blob.get_u32("shield time") < uint(8 + difficulty * 1.33f + XORRandom(20));
	bool backOffTime = gametime - blob.get_u32("backoff time") < uint(1 + XORRandom(20));

	if (target.isKeyPressed(key_action1))   // enemy is attacking me
	{
		int r = XORRandom(35);
		if (difficulty > 2 && r < 2 && (!backOffTime || difficulty > 4))
		{
			blob.set_u32("shield time", gametime);
			shieldTime = true;
		}
		else if (difficulty > 1 && r > 32 && !shieldTime)
		{
			// raycast to check if there is a hole behind

			Vec2f raypos = mypos;
			raypos.x += targetPos.x < mypos.x ? 32.0f : -32.0f;
			Vec2f col;
			if (getMap().rayCastSolid(raypos, raypos + Vec2f(0.0f, 32.0f), col))
			{
				blob.set_u32("backoff time", gametime);								    // base on difficulty
				backOffTime = true;
			}
		}
	}
	else
	{
		// start attack
		if (XORRandom(Maths::Max(3, 30 - (difficulty + 4) * 2)) == 0 && (getGameTime() - blob.get_u32("attack time")) > 10)
		{

			// base on difficulty
			blob.set_u32("attack time", gametime);
		}
	}

	if (shieldTime)   // hold shield for a while
	{
		blob.setKeyPressed(key_action2, true);
	}
	else if (backOffTime)   // back off for a bit
	{
		Runaway(blob, target);
	}
	else if (targetDistance < 40.0f && getGameTime() - blob.get_u32("attack time") < (Maths::Min(13, difficulty + 3))) // release and attack when appropriate
	{
		if (!target.isKeyPressed(key_action1))
		{
			blob.setKeyPressed(key_action2, false);
		}

		blob.setKeyPressed(key_action1, true);
	}
}

CBlob@ getNewTarget(CBlob@ blob)
{
	CBlob@[] players;
	getBlobsByTag("player", @players);

	CBlob@ closest = null;
	f32 closestDist = 600.0f;
	for (uint i = 0; i < players.length; i++)
	{
		CBlob@ potential = players[i];
		if (blob.getTeamNum() == potential.getTeamNum()) continue;
		if (potential.hasTag("dead") || potential.hasTag("migrant")) continue;
		
		const f32 dist = (potential.getPosition() - blob.getPosition()).Length();
		if (dist < closestDist)
		{
			@closest = potential;
			closestDist = dist;
		}
	}
	return closest;
}

/// PATHING DEBUG

void onRender(CSprite@ this)
{
	if (!render_paths) return;

	CBlob@ blob = this.getBlob();
	if (blob.hasTag("dead")) return;

	PathHandler@ handler;
	if (!blob.get("path_handler", @handler)) return;

	const SColor col(0xff66C6FF);
	Driver@ driver = getDriver();
	
	// Draw low-level boundary
	//GUI::DrawCircle(blob.getScreenPos(), tilesize * 15 * 2 * getCamera().targetDistance, col);
	
	// Draw high-level boundary
	//GUI::DrawCircle(blob.getScreenPos(), tilesize * 70 * 2 * getCamera().targetDistance, ConsoleColour::ERROR);

	// Draw target position
	/*if (handler.destination != Vec2f_zero)
	{
		Vec2f destination = driver.getScreenPosFromWorldPos(handler.destination);
		GUI::DrawCircle(destination, 16.0f, ConsoleColour::ERROR);
	}*/

	// Draw low-level path
	for (int i = 1; i < handler.path.length; i++)
	{
		Vec2f current = driver.getScreenPosFromWorldPos(handler.path[i]);
		Vec2f previous = driver.getScreenPosFromWorldPos(handler.path[i - 1]);
		GUI::DrawArrow2D(previous, current, col);
	}
	
	// Draw stuck nodes
	const string[]@ cached_keys = handler.cached_waypoints.getKeys();
	for (int i = 0; i < cached_keys.length; i++)
	{
		CachedWaypoint@ cached_waypoint;
		if (!handler.cached_waypoints.get(cached_keys[i], @cached_waypoint)) continue;
		
		if (handler.waypoints.length > 0 && handler.waypoints[0] == cached_waypoint.position) continue;

		Vec2f stuck_waypoint = driver.getScreenPosFromWorldPos(cached_waypoint.position);
		GUI::DrawCircle(stuck_waypoint, 10.0f, cached_waypoint.stuck ? ConsoleColour::CRAZY : ConsoleColour::WARNING);
	}
	
	if (handler.waypoints.length > 0)
	{
		// Draw high level path
		/*for (int i = 1; i < handler.waypoints.length; i++)
		{
			Vec2f waypoint = driver.getScreenPosFromWorldPos(handler.waypoints[i]);
			GUI::DrawCircle(waypoint, 9.0f, ConsoleColour::RCON);
		}*/

		// Draw current waypoint goal
		Vec2f next_waypoint = driver.getScreenPosFromWorldPos(handler.waypoints[0]);
		GUI::DrawCircle(next_waypoint, 8.0f, col);
	}
}
