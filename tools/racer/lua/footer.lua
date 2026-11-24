-- Kestrel Racing, reference harness footer (ours): builds the engine's track model from KTRK (our generated
-- oval), runs the engine's _update order for RACER_TICKS ticks and dumps the raw 16.16 state of every car.

local function build_track()
	local V,F,ground={},{},{}
	for i,c in ipairs(KTRK.v) do V[i]={c[1],c[2],c[3]} end
	for i,fd in ipairs(KTRK.f) do
		local f={flags=fd.flags,id=i}
		f.ni=band(f.flags,2)>0 and 4 or 3
		for k=1,f.ni do f[k]=V[fd.v[k]] end
		local nb=band(shr(f.flags,5),7)
		if nb>0 then
			f.borders={}
			for k=1,nb do
				local a,b=f[fd.borders[k]+1],f[(fd.borders[k]+1)%f.ni+1]
				local bn=make_v(b,a)
				bn[2]=0
				bn=v_normz(bn)
				add(f.borders,{v=a,n={bn[3],0,-bn[1]}})
			end
		end
		f.n=v_normz(v_cross(make_v(f[1],f[f.ni]),make_v(f[1],f[2])))
		f.cp=v_dot(f.n,f[1])
		F[i]=f
	end
	for id,list in pairs(KTRK.ground) do
		ground[id]={}
		for _,fi in ipairs(list) do add(ground[id],F[fi]) end
	end
	local segs,n={},#KTRK.line
	for i=0,n-1 do
		local l0,r0=V[KTRK.line[i+1][1]],V[KTRK.line[i+1][2]]
		local nx=KTRK.line[(i+1)%n+1]
		local l1,r1=V[nx[1]],V[nx[2]]
		add(segs,v_normz(v2_ortho(make_v(l0,r0),1)))
		add(segs,l0)
		add(segs,r0)
		add(segs,v_len(make_v(l0,l1)))
		add(segs,v_len(make_v(r0,r1)))
	end
	return {ground=ground,segments=segs}
end
track=build_track()

-- count wall hits (the engine calls the global face_collide each tick)
local face_collide0=face_collide
function face_collide(f,p,r)
	local hit,force,n=face_collide0(f,p,r)
	if(hit) HITS+=1
	return hit,force,n
end

local function autopilot(car)
	local _,l,r=car.track:get_next(3)
	local to=make_v(car.pos,v_lerp(l,r,0.5))
	local fwd=m_fwd(car.m)
	local e=(fwd[1]*to[3]-fwd[3]*to[1])/max(v_len(to),0.001)
	local b=16
	if(e>0.02) b=bor(b,1)
	if(e<-0.02) b=bor(b,2)
	return b
end

local function buttons(t,car)
	if(RACER_INPUTS) return RACER_INPUTS[t] or 0
	if(RACER_RAM) return 16
	if(RACER_SCENARIO=="wall") return 18
	return autopilot(car)
end

-- coverage counters (the dump's last two columns): contacts the engine reports (sfx 53), NPC hard-braking steers
local CONTACTS,NBRAKE=0,0
function sfx(n) if(n==53) CONTACTS+=1 end

local function spawn(g,maker)
	local car=maker(v_clone(g.pos),g.yaw,make_track(track.segments,g.seg))
	car.m=make_m_from_euler(0,g.yaw,0)
	local steer0=car.steer
	car.steer=function(self,dt,rpm,braking,npc)
		if(braking and npc) NBRAKE+=1
		return steer0(self,dt,rpm,braking,npc)
	end
	return car
end

local plyr=spawn(KTRK.grid[1],make_plyr)
-- observe the wheel state the engine hands to update_parts: total wheel turn, steering angle, sliding
local PARTS={0,0,false}
local update_parts0=plyr.update_parts
plyr.update_parts=function(self,tr,sa,sl)
	PARTS={tr,sa,sl}
	update_parts0(self,tr,sa,sl)
end
local npcs={}
for k=2,1+RACER_NPCS do add(npcs,spawn(KTRK.grid[k],make_npc)) end

-- the ram scenario: NPC 1 parked 6 m ahead of the player and never steered, so the player drives into it
if RACER_RAM then npcs[1].pos=v_add(plyr.pos,m_fwd(plyr.m),6) end

local function row(t,id,car,b)
	local p,a=car:get_pos()
	local v=car:get_velocity()
	local f=car:get_ground()
	local out={tostr(t),tostr(id)}
	for _,x in pairs({p[1],p[2],p[3],v[1],v[2],v[3],a,f and f.id or 0,car.track:get_u(),car.track:get_v()}) do
		add(out,tostr(x,true))
	end
	add(out,tostr(b))
	add(out,tostr(HITS))
	add(out,tostr(CONTACTS))
	add(out,tostr(NBRAKE))
	if id==0 then
		add(out,tostr(PARTS[1],true))
		add(out,tostr(PARTS[2],true))
		add(out,PARTS[3] and "1" or "0")
	else
		add(out,"0x0000.0000")
		add(out,"0x0000.0000")
		add(out,"0")
	end
	print(table.concat(out,"\t"))
end

print("tick\tcar\tpx\tpy\tpz\tvx\tvy\tvz\tangle\tface\tu\tv\tbtn\thits\tsfx\tnbrake\ttr\tsa\tslide")
for t=1,RACER_TICKS do
	if t>=RACER_COUNTDOWN then BTN=buttons(t,plyr) else BTN=0 end
	-- RACER_HOLD: the race's grid + countdown: no car moves before the player's control starts (the engine's NPCs would drive)
	if not RACER_HOLD or t>=RACER_COUNTDOWN then
		if(t>=RACER_COUNTDOWN) plyr:control()
		plyr:update_contacts(npcs)
		plyr:prepare()
		plyr:integrate()
		plyr:update()
		for i,npc in pairs(npcs) do
			if not (RACER_RAM and i==1) then npc:control() end
			npc:prepare()
			npc:integrate()
			npc:update()
		end
		skidmarks:update()
	end
	row(t,0,plyr,BTN)
	for i,npc in pairs(npcs) do row(t,i,npc,0) end
end
