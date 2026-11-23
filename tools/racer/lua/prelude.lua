-- Kestrel Racing, reference harness prelude (ours). Runs before the engine functions, under z8lua (PICO-8's
-- 16.16 numbers, sin/cos/atan2 tables). Gives the engine the PICO-8 globals z8lua lacks and stubs what the
-- physics touches but does not need (sound, camera shake, memory). RACER_* globals are set by ref_harness.py.

function add(t,v) t[#t+1]=v return v end
function del(t,v)
	for i=1,#t do
		if t[i]==v then
			for j=i,#t do t[j]=t[j+1] end
			return v
		end
	end
end
-- iterate a snapshot: deleting while looping skips nothing (the engine only deletes skidmarks)
function all(t)
	local c,i={},0
	for k=1,#t do c[k]=t[k] end
	return function() i+=1 return c[i] end
end
unpack=table.unpack

function sfx() end
function music() end
function peek() return 0 end
function poke() end
function stat() return 0 end
function rnd() return 0 end
cam={shake=function() end}

-- buttons: bit 0 left, 1 right, 4 accelerate, 5 brake (btn(i) of the engine)
BTN=0
function btn(i) return band(shr(BTN,i),1)==1 end

-- own car model stub (the engine reads wheel offsets for skidmarks); values are ours
local wheel=function(x,z) return {offset={x,0,z}} end
local all_models={car={lods={[2]={vgroups={lfw=wheel(-0.3,0.4),rfw=wheel(0.3,0.4),lrw=wheel(-0.3,-0.4),rrw=wheel(0.3,-0.4)}}}}}

HITS=0
