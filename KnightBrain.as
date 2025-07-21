// Knight brain

#define SERVER_ONLY

#include "BrainCommon.as"
#include "BrainPathing.as"

// Gingerbeard @ March 6th, 2025

// here is an example of a pathing implementation for a bot


void onInit(CBrain@ this)
{
	InitBrain(this);
	
	this.server_SetActive(true);

	CBlob@ blob = this.getBlob();
	BrainPath pather(blob, Path::GROUND);
	blob.set("brain_path", @pather);
}

void onTick(CBrain@ this)
{
	CBlob@ blob = this.getBlob();

	BrainPath@ pather;
	if (!blob.get("brain_path", @pather)) return;

	if (blob.getPlayer() !is null && !blob.isBot())
	{
		pather.EndPath();
		this.server_SetActive(false);
		return;
	}

	pather.Tick();

	pather.SetSuggestedKeys();
	pather.SetSuggestedAimPos();

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
			pather.SetPath(blob.getPosition(), target.getPosition());
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
			pather.EndPath();
			AttackBlob(blob, target);
		}

		// lose target if its killed (with random cooldown)

		if (LoseTarget(this, target))
		{
			pather.EndPath();
			strategy = Strategy::idle;
		}

		blob.set_u8("strategy", strategy);
	}
	else if (strategy == Strategy::idle)
	{
		// wander around the map
		if (!pather.isPathing())
		{
			CMap@ map = getMap();
			Vec2f dim = map.getMapDimensions();
			pather.SetPath(blob.getPosition(), Vec2f(XORRandom(dim.x), XORRandom(dim.y)));
		}
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
	if ((!render_paths && g_debug == 0) || g_debug == 5) return;

	CBlob@ blob = this.getBlob();
	if (blob.hasTag("dead")) return;

	BrainPath@ pather;
	if (!blob.get("brain_path", @pather)) return;

	pather.Render();
}
