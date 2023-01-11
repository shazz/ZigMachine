var basepath="screens/206/";
 
var player = new music("MK");
//player.stereo(true);
player.LoadAndRun(basepath+'cavofaby.mod');
 
var mycanvas;
var mycanvasF;
var mycanvasS;
var mytexture;
var done=0;
var imgData;
var frameBuffer;
var imgDataDST;
var frameBufferDST;

var map_2 = {
	dist_min : 0.5,
	dist_max : 4.5,
	dist_step : 0.001,
	angle_step : 0.002,
	base_radius : 400.0,
	width : 640,
	height : 480,
	image_width : 512,
	image_height : 512,
	table : [],
	shade : []
	};
	
function prec(map) {
	for(var i = 0; i < map.width * map.height; i++) { map.table[i] = 0; map.shade[i] = 0; };

	var image_xdelta = (map.image_width * 2) / (Math.PI * 2);
	var image_ydelta = (map.image_height * 2) / map.dist_max;
	var xCenter = map.width / 2;
	var yCenter = map.height / 2;

	for(var dist = map.dist_max; dist > map.dist_min; dist -= map.dist_step) {
		for(var angle = Math.PI * 2; angle > 0; angle -= map.angle_step) {
			// flower tunnel
			var radius = 250//( Math.cos( angle * 4.0 ) + 1.0 ) * map.base_radius / 6.0  + map.base_radius / 2.0;
			//	basic, round, tunnel
			//var radius = map.base_radius / 2.0;
			radius = radius / dist;
			var x = Math.floor(Math.cos(angle) * radius * 1.2) + xCenter;
			var y = Math.floor(Math.sin(angle) * radius) + yCenter;

			if( (x >= 0) && (x < map.width) && (y >= 0) && (y < map.height) ) {  
				map.table[y * map.width + x] = (Math.floor(image_ydelta * dist) % map.image_height) * map.image_width + (Math.floor(image_xdelta * angle) % map.image_width);
				map.shade[y * map.width + x] = 255 - Math.floor( dist / map.dist_max * 255.0 )+20;
				}
	  		}
		}
}
	
function render(frame, width, height) {
    if(frameBuffer == undefined) return;

    var timestamp = new Date().getTime();
    timestamp = Math.floor(timestamp / 4);
    
    var texture = frameBuffer;
    var map = map_2;

	var offsetX = Math.floor(Math.cos(timestamp / 420) * map.width / 4 + map.width / 4);
	var offsetY = Math.floor(Math.sin(timestamp / 300) * map.height / 6 + map.width / 4);

    var i = 0;
    var h = height;
    while (h--) {
      var w = width;
      while (w--) {
		var lut = (h + offsetY) * map.width + w + offsetX;
		var texel = map.table[lut];
		texel = ((texel + timestamp * 512) & 0x3ffff ) << 2;
        frame[i++] = texture[texel++];
        frame[i++] = texture[texel++];
        frame[i++] = texture[texel];
        frame[i++] = map.shade[lut];
      }
    }
  }

var mylogo=new image(basepath+'wab_1.png');
var myfont = new image(basepath+'font_rep.png');

var myback=new image(basepath+'texture.png');
myback.img.onload = function() { initpre() ; }
	
function initpre(){
	mytexture=new canvas(512,512);
	myback.draw(mytexture,0,0);
	imgData = mytexture.contex.getImageData(0, 0, 512, 512);
    frameBuffer = imgData.data;
	prec(map_2);
	done=1;
}
 

function prego(){
    if ( done==1 )
        go() ;
    else
        requestAnimFrame( prego );
}
 
function init(){
	mylogo.setmidhandle();
	mycanvas=new canvas(320,240);
	mycanvasF=new canvas(640,480,"main");
	mycanvasS=new canvas(640,48);
	myfont.initTile(32,32,32);
	myscrolltext = new scrolltext_horizontal();
	myscrolltext.scrtxt="YEAHHH !!! I AM BACK WITH A NEW TINY INTRO, THIS TIME I WANTED TO TEST OLDSKOOL FRAMEBUFFER / VIDEO RAM EMULATION, MEANING I DRAW EACH PIXEL OF THE CANVAS ;) PRETTY FAST, AT LEAST ON MY SIDE. AND NOW THE SO AWAITED GREETING PART : TOTORMAN, SOLO, MELLOWMAN, JACE, NEW CORE, SHAZZ/TRSI, SINK, BOSS, JEAN KULE, LARS, IMPERATOR, AXEL D WIZZ, JOHN M., ERIC V., JANNE, PIERRE AND ALL CODEF FACEBOOK MEMBERS... TIME TO WRAPPPPPPPP.....          ";
	myscrolltext.init(mycanvasS,myfont,1);
    imgDataDST = mycanvas.contex.createImageData(320, 240);
    frameBufferDST = imgDataDST.data;
	prego();
}
 
function go(){
	render(frameBufferDST,320,240);
	  mycanvas.contex.putImageData(imgDataDST, 0, 0);
	
	mycanvasF.fill("#000000");
	mycanvasS.clear();
	mycanvas.draw(mycanvasF,0,0,1,0,2,2);
	mylogo.draw(mycanvasF,320,200);
	myscrolltext.draw(0);
	mycanvasS.draw(mycanvasF,0,480-48,0.2,0);

	requestAnimFrame( go );
}
 
