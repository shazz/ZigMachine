var font = new image('screens/028/fonts2.png');
var fontMask = new image('screens/028/fontsMask3.png');
var logo = new image('screens/028/logo.png');
var background = new image('screens/028/background.png');
var backgroundMask = new image('screens/028/backgroundMask.png');

var rasterBlue = new image('screens/028/rasterBlue.png');
var rasterGray = new image('screens/028/rasterGray.png');
var rasterYellow = new image('screens/028/rasterYellow.png');
var rasterPink = new image('screens/028/rasterPink.png');
var rasterFonts = new image('screens/028/rasterFont4.png');

var maincanvas;
var scrolltext;
var mergecanvas;
var scrollcanvas;

var rastersCanvas;

var offscreencanvas;
var fx;
var fxparam=[
		{value: 0, amp: 20, inc:0.06, offset: -0.06},
	      ];

var player = new music("YM");

function init()
{
	player.LoadAndRun('screens/028/Pro BMX Simulator A.ym');

	maincanvas=new canvas(640,400,"main");
	offscreencanvas=new canvas(640,326);
	mergecanvas=new canvas(640,326);
	scrollcanvas=new canvas(640, 60);

	rastersCanvas=new canvas(640,360);
	for(var i=0; i<6; i++){
		rasterFonts.draw(rastersCanvas,0,i*60);
	}

	//this.initTile=function(tilew,tileh,tilestart){
	rasterFonts.initTile(640,2);

	logo.draw(offscreencanvas,18,0);

	font.initTile(32,32,32);
	scrolltext = new scrolltext_horizontal();
	scrolltext.scrtxt=" THE UNION PRESENTS : - GARFIELD - CRACKED BY DOM FROM THE REPLICANTS MEMBER OF THE UNION. MEMBERS OF THE REPLICANTS ARE : ELWOOD(NEW MEMBER!!),DOM,<R.AL>,SNAKE,COBRA,KNIGHT 2OO1,GO HAINE,EXCALIBUR,RANK-XEROX,HANNIBAL,GOLDORAK...... HI TO : LOCKBUSTERS,THE BLADE RUNNERS,B.O.S.S,WAS (NOT WAS),MCA,THE PREDATORS     A SPECIAL HI TO ALL MEMBERS OF THE MICRO CLUB LILLOIS!!!!!!!!........BYE BYE.......SEE YOU A NEXT TIME....      ";
	scrolltext.init(scrollcanvas,font,3.5);

	fx=new FX(offscreencanvas,mergecanvas,fxparam);

	go();
}

var logoTop = 16;
var logoBottom = 282;
var logoPos = 16;
var logoPosInc = 1.8;

var rastersTop = 50;
var rastersBottom = 270

var rasterBluePos = rastersTop;
var rasterBluePosInc = 1.5;
var rasterPinkPos = rastersTop+100;
var rasterPinkPosInc = 1.5;
var rasterYellowPos = rastersTop+200;
var rasterYellowPosInc = 1.5;
var rasterGrayPos = 192;
var rasterGrayPosInc = -1.5;

var rasterFontPos = 0;
//var a = 0;

function go()
{
	maincanvas.fill('#000000');
	mergecanvas.clear();
	scrollcanvas.clear();

	fx.sinx(0,0);
	logoPos += logoPosInc;
	if(logoPos  <= logoTop+10) logoPosInc = 1.8;
	if(logoPos  >= logoBottom) logoPosInc = -1.8


	// draw rasters
	rasterBlue.draw(maincanvas, 0, rasterBluePos);
	rasterBluePos += rasterBluePosInc
	if(rasterBluePos < rastersTop || rasterBluePos > rastersBottom)  rasterBluePosInc = -rasterBluePosInc;

	rasterPink.draw(maincanvas, 0, rasterPinkPos);
	rasterPinkPos += rasterPinkPosInc
	if(rasterPinkPos < rastersTop || rasterPinkPos > rastersBottom)  rasterPinkPosInc = -rasterPinkPosInc;

	rasterYellow.draw(maincanvas, 0, rasterYellowPos);
	rasterYellowPos += rasterYellowPosInc
	if(rasterYellowPos < rastersTop || rasterYellowPos > rastersBottom)  rasterYellowPosInc = -rasterYellowPosInc;

	rasterGray.draw(maincanvas, 0, rasterGrayPos);
	rasterGrayPos += rasterGrayPosInc
	if(rasterGrayPos < rastersTop || rasterGrayPos > rastersBottom)  rasterGrayPosInc = -rasterGrayPosInc;

	// draw background
	background.draw(maincanvas, 0, 0);

	// scrolltext
	scrolltext.draw(26);
	scrollcanvas.contex.globalCompositeOperation='source-atop';
	fontMask.draw(scrollcanvas, 0, 0);
	scrollcanvas.draw(maincanvas, 32, 316);
	scrollcanvas.contex.globalCompositeOperation='source-over';

	// draw raster fonts inside logo using source-atop
	mergecanvas.contex.globalCompositeOperation='source-in';

	// draw rasters back scroller
	var dir = 0;
	if(logoPosInc > 0) dir = -1; else dir = 1;

	/* works well with tiles but only on chrome :(
	a+=1.8;
	for(var i=0; i<230/2;i++)
	{
		rasterFonts.drawTile(mergecanvas,((dir*i)+a)%30, 0,60 + (i*2));
	}
	*/

	rastersCanvas.draw(mergecanvas,0,rasterFontPos);
	rasterFontPos -= (dir*3);
	if(rasterFontPos >=60) rasterFontPos=0;
	if(rasterFontPos <=-60) rasterFontPos=0;


	// draw resulting buffer on screen canvas
	mergecanvas.drawPart(maincanvas, 50,logoPos, 0,logoPos-logoTop, 640, 58, 1.0, 0, 1.0, 1.0);
	mergecanvas.contex.globalCompositeOperation='source-over';

	// draw mask
	backgroundMask.draw(maincanvas, 0,294);

	counter++;
	requestAnimFrame( go );
}

var counter = 0;

