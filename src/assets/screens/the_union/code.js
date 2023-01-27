var player = new music("YM");
//player.stereo(true);
player.LoadAndRun('screens/014/Scout.ym');

var mycanvas;
var my2dstarfield;
var my2dstarsparams=[
		{nb:25, speedy:0, speedx:-5.0, color:'#E0E0E0', size:2},
		{nb:30, speedy:0, speedx:-1.2, color:'#606060', size:2},
              ];

var logo=new image('screens/014/logo.png');
var logosinx = 0;
var logoInc = 0;

var esfont = new image('screens/014/fonts.png');
var scrolltext;

var fontbackground=new image('screens/014/back.png');
var fontbackgroundblue=new image('screens/014/backblue.png');

var sprites = new Array();
sprites[0]=new image('screens/014/DELTA.png');
sprites[1]=new image('screens/014/DELTA.png');
sprites[2]=new image('screens/014/DELTA.png');
sprites[3]=new image('screens/014/H.png');
sprites[4]=new image('screens/014/O.png');
sprites[5]=new image('screens/014/W.png');
sprites[6]=new image('screens/014/D.png');
sprites[7]=new image('screens/014/Y.png');
sprites[8]=new image('screens/014/DELTA.png');
sprites[9]=new image('screens/014/DELTA.png');
sprites[10]=new image('screens/014/DELTA.png');

var spritesPos = new Array();
spritesPos[0]=0.3*1;
spritesPos[1]=0.3*2;
spritesPos[2]=0.3*3;
spritesPos[3]=0.3*4;
spritesPos[4]=0.3*5;
spritesPos[5]=0.3*6;
spritesPos[6]=0.3*7;
spritesPos[7]=0.3*8;
spritesPos[8]=0.3*9;
spritesPos[9]=0.3*10;
spritesPos[10]=0.3*11;

// ------------------------------------------------------------------------------
// Functions
// ------------------------------------------------------------------------------


function init()
{
	mycanvas=new canvas(640,400,"main");
	starcanvas=new canvas(640,190);
	scrollcanvas=new canvas(640,17*2);
	bluebackcanvas=new canvas(640,174);

	my2dstarfield=new starfield2D_dot(starcanvas,my2dstarsparams);

	logo.setmidhandle();

	esfont.initTile(32*2,17*2,32);
	scrolltext = new scrolltext_horizontal();
	scrolltext.scrtxt="THE EXCEPTIONS PROUDLY PRESENT THIS NEW GAME CRACKED BY HOWDY FROM THE EXCEPTIONS MEMBER OF THE UNION     LET WRAP              ";
	scrolltext.init(scrollcanvas,esfont,3);

	go();
}

function go()
{
	mycanvas.fill('#000000');
	starcanvas.clear();
	scrollcanvas.clear();

	my2dstarfield.draw();
	starcanvas.drawPart(mycanvas, 0,0, 0,0, 640,190, 1.0, 0, 1.0, 1.0);

	logosinx+=0.13;
	logoInc += 0.008;
	logo.draw(mycanvas,320 + Math.sin(logosinx)*(100*Math.sin(logoInc)),194/2);

	for (counter = 0; counter < 11; counter++)
	{
		spritesPos[counter] += 0.04;
		sprites[counter].draw(mycanvas, 305 + 306*Math.sin(spritesPos[counter]), 86 + 84*Math.cos(spritesPos[counter]*1.5) );
	}

	// dessine le fond rouge
	fontbackground.draw(mycanvas,0,233);

	// dessine le fond bleu dans un buffer
	fontbackgroundblue.draw(bluebackcanvas,0, 0);

	// dessine le scrolltext dans un buffer
	scrolltext.draw(0);

	// dessine le buffer du fond bleu dans celui du scrolltext en mode ?
	scrollcanvas.contex.globalCompositeOperation='source-atop';
	bluebackcanvas.drawPart(scrollcanvas, 0,0, 0,63, 640,17*2, 1.0, 0, 1.0, 1.0);

	// dessine le buffer complet sur le canvas sans alpha blend
	scrollcanvas.drawPart(mycanvas, 0,296, 0,0, 640,17*2, 1.0, 0, 1.0, 1.0);

	scrollcanvas.contex.globalCompositeOperation='source-over';

	requestAnimFrame( go );
}

