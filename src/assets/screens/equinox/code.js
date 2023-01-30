
<!DOCTYPE HTML>
<html>
<head>
<script> 
/*------------------------------------------------------------------------------ 
Copyright (c) 2011 Antoine Santo Aka NoNameNo

This File is part of the CODEF project.

More info : http://codef.santo.fr
Demo gallery http://www.wab.com

Permission is hereby granted, free of charge, to any person obtaining a copy
of this software and associated documentation files (the "Software"), to deal
in the Software without restriction, including without limitation the rights
to use, copy, modify, merge, publish, distribute, sublicense, and/or sell
copies of the Software, and to permit persons to whom the Software is
furnished to do so, subject to the following conditions:

The above copyright notice and this permission notice shall be included in
all copies or substantial portions of the Software.

THE SOFTWARE IS PROVIDED "AS IS", WITHOUT WARRANTY OF ANY KIND, EXPRESS OR
IMPLIED, INCLUDING BUT NOT LIMITED TO THE WARRANTIES OF MERCHANTABILITY,
FITNESS FOR A PARTICULAR PURPOSE AND NONINFRINGEMENT. IN NO EVENT SHALL THE
AUTHORS OR COPYRIGHT HOLDERS BE LIABLE FOR ANY CLAIM, DAMAGES OR OTHER
LIABILITY, WHETHER IN AN ACTION OF CONTRACT, TORT OR OTHERWISE, ARISING FROM,
OUT OF OR IN CONNECTION WITH THE SOFTWARE OR THE USE OR OTHER DEALINGS IN
THE SOFTWARE.
------------------------------------------------------------------------------*/
</script>
<script src="//codef.santo.fr/codef/codef_music.js"></script> 
<script src="//codef.santo.fr/codef/codef_core.js"></script>
<script src="//codef.santo.fr/codef/codef_scrolltext.js"></script>
<script src="screens/015/fsm.js"></script>
<script>
var player = new music("YM");
//player.stereo(true);
player.LoadAndRun('screens/015/Cybernoid2.ym');

var mycanvas;
var logocanvas;
var roadcanvas1;
var roadcanvas2;

var esfont = new image('screens/015/fonts.png');
var scrolltext;

var road1=new image('screens/015/road1.png');
var road2=new image('screens/015/road2.png');
var logo=new image('screens/015/logo.png');

var backscroll=new image('screens/015/backscroll.png');
var backtop=new image('screens/015/backtop.png');

var sprites = new Array();
sprites[0]=new image('screens/015/dragon1.png');
sprites[1]=new image('screens/015/dragon2.png');
sprites[2]=new image('screens/015/dragon3.png');
sprites[3]=new image('screens/015/dragon4.png');
sprites[4]=new image('screens/015/dragon5.png');
sprites[5]=new image('screens/015/dragon6.png');
sprites[6]=new image('screens/015/dragon7.png');
sprites[7]=new image('screens/015/dragon8.png');

var frames 	= 1;
var tabpos = 0;

var road_offsets=
[
		[ 0, 2, 4, 6, 14, 20, 28, 38, 58],
		[ 0, 2, 4, 8, 14, 22, 28, 40, 52],
		[ 0, 2, 6, 8, 14, 22, 30, 42, 46],
		[ 0, 4, 4, 8, 16, 24, 30, 44, 40],
		[ 0, 4, 4, 10, 16, 24, 32, 46, 34],
		[ 0, 4, 6, 10, 16, 26, 32, 48, 28],
		[ 0, 4, 6, 12, 16, 26, 34, 52, 20],
		[ 0, 6, 4, 12, 20, 26, 34, 54, 14],
		[ 0, 6, 6, 12, 20, 26, 36, 56, 8],
		[ 2, 4, 6, 14, 20, 28, 38, 58, 0],
		[ 2, 4, 8, 14, 22, 28, 40, 52, 0],
		[ 2, 6, 8, 14, 22, 30, 42, 46, 0],
		[ 4, 4, 8, 16, 24, 30, 44, 40, 0],
		[ 4, 4, 10, 16, 24, 32, 46, 34, 0],
		[ 4, 6, 10, 16, 26, 32, 48, 28, 0],
		[ 4, 6, 12, 16, 26, 34, 52, 20, 0],
		[ 6, 4, 12, 20, 26, 34, 54, 14, 0],
		[ 6, 6, 12, 20, 26, 36, 56, 8, 0],

];

var road_sum=
[
		[ 0, 0, 2, 6, 12, 26, 46, 74, 112, 170],
		[ 0, 0, 2, 6, 14, 28, 50, 78, 118, 170],
		[ 0, 0, 2, 8, 16, 30, 52, 82, 124, 170],
		[ 0, 0, 4, 8, 16, 32, 56, 86, 130, 170],
		[ 0, 0, 4, 8, 18, 34, 58, 90, 136, 170],
		[ 0, 0, 4, 10, 20, 36, 62, 94, 142, 170],
		[ 0, 0, 4, 10, 22, 38, 64, 98, 150, 170],
		[ 0, 0, 6, 10, 22, 42, 68, 102, 156, 170],
		[ 0, 0, 6, 12, 24, 44, 70, 106, 162, 170],
		[ 0, 2, 6, 12, 26, 46, 74, 112, 170, 0],
		[ 0, 2, 6, 14, 28, 50, 78, 118, 170, 0],
		[ 0, 2, 8, 16, 30, 52, 82, 124, 170, 0],
		[ 0, 4, 8, 16, 32, 56, 86, 130, 170, 0],
		[ 0, 4, 8, 18, 34, 58, 90, 136, 170, 0],
		[ 0, 4, 10, 20, 36, 62, 94, 142, 170, 0],
		[ 0, 4, 10, 22, 38, 64, 98, 150, 170, 0],
		[ 0, 6, 10, 22, 42, 68, 102, 156, 170, 0],
		[ 0, 6, 12, 24, 44, 70, 106, 162, 170, 0],
];

var spritesPosX = new Array();
var spritesPosY = new Array();

var counter = 0;
var offset_y = 226;

var sleepingTime = 0;
var aliveTime = 0;
var morphTime = 0;
var demorphTime = 0;

var morphType = 7;
var	aliveInc = 1;
var alpha = 0.00000001;
var timeToShowLogo = 0;
var	logoInc = 0.1;
var alphaTime = 0;

// ------------------------------------------------------------------------------
// Functions
// ------------------------------------------------------------------------------

function init()
{
	mycanvas=new canvas(640,400+(28*2),"main");
	logocanvas=new canvas(406,46);
	logo.draw(logocanvas,0,0);

	roadcanvas1 = new canvas(640,170);
	road1.draw(roadcanvas1,0,0);

	roadcanvas2 = new canvas(640,170);
	road2.draw(roadcanvas2,0,0);

	esfont.initTile(32*2,26*2,32);
	scrolltext = new scrolltext_horizontal();
	scrolltext.scrtxt="EQUINOX PRESENTS RVF HONDA CRACKED BY ILLEGAL ,INTRO CODED BY KRUEGER ( HE IS NOT HERE BECAUSE HE WORKS AS DUSTMAN,DON T LAUGH THAT S REAL ) ,GRAPHIXX BY SMILEY ,ACRONYM BY EIDOLON...             MEMBERS OF EQUINOX ARE :COMPUTER JONES,CREENOX,EIDOLON,ELIAS,ILLEGAL,KRUEGER ( HEHEHE! ),SMILEY,STEPRATE,TDS ( DROP YOUR GIRL FRIEND AND COME HOME ),WEREWOLF ,ZOOLOOK.            GREETINGS TO :MDK (SEE YOU SOON),ST CNX ( WHEN WILL ARRIVE THE TETARD DEMO ),MCA ( HELLO HARRIE ),THE REPLICANTS  ( GOOD INTRO FURY ),DMA ( CHON CHON AND CAMERONE ),THE OVERLANDERS ( BIG THANKS FOR SWAPPING US !),SECTOR NINETY NINE,MEGABUGS,MCS,TBC ( HI DOC )...            HI TO : SID,TOXIC,CHUD,RED SHARK,INFERNAL CODER,BEGON JAUNE,TRAHISON (HE TOI LA BAS ,POURQUOI TU MARCHES COMME CA ? C EST LE RAP,RAP DES GARCONS BOUCHER),POKE,BO,MAGNUM FORCE,FISHERMAN,JULES,BUB,TESTO,EXCALIBURP,JOHNNY TGB,ALX,STRIDER,NOBRU,BABEBIBOBU GROUP,CHRISTINA AND GWENDOLINE FROM ST RANGE...            MESSAGE FROM STEPRATE :TU CONNAIS RIGOULOSS ? SI TU NE CONNAIS PAS VIENS ME VOIR DANS LA CABINE TELEPHONIQUE LA PLUS PROCHE !!!            MESSAGE FROM EIDOLON :JE VOUDRAIS DIRE QUE C EST MIEUX QUE MIEUX ET QUE KRUEGER IL PEUT PAS DIRE LE CONTRAIRE ( ELIAS T EST VIVANT DEPUIS SAMEDI ?)            MESSAGE FROM WEREWOLF :J AIME LES DES SEINS ZA NIMEES ,VIVE MOI !            MESSAGE FROM ILLEGAL LE BAVEUX :HEU TU COMPRENDS J AI TRENTE ANS D ASSEMBLEUR DEVANT MOI ALORS C EST PAS UN SWAPPER DE MERDE QUI VA ME FAIRE CHIER BORDEL!,FUCK!,EIDOLON!!! ( HIHIHIHI! )            MESSAGE FROM KRUEGER :JE SUIS SUR MA BENNE ET J AIME CA ,A DEMAIN LES MECS !            MESSAGE FOR SMILEY : SI TU CONTINUES T AURA UNE TAPETTE !!!            MESSAGE FOR COMPUTER JONES : BON ON A RIEN A TE DIRE SAUF QUE TA MINI ELLE PUE ET TDS IL TE GRUGE AVEC SA RENAULT CINQ TURBO DIESEL  !            MESSAGE FROM ZOOLOOK : CA FAIT DIX ANS QUE JE SUIS SUR MA DEMO MAIS JE CROIS QUE JE VAIS LA RECOMMENCER POUR CHANGER UN PEU ...            BYE ENJOY THIS FANTASTICOULOUS GAME ....SEE YOU LATER !!!!                                          ";
	scrolltext.init(mycanvas,esfont,13);

	spritesFsm = new FSM( "in_egg" );
    spritesFsm.add_transition( "awake", "in_egg", null, "morphing" );
    spritesFsm.add_transition( "morph", "morphing", null, "alive" );
    spritesFsm.add_transition( "deaden", "alive", null, "demorphing" );
    spritesFsm.add_transition( "demorph", "demorphing", null, "in_egg" );

	// precalc sprites trajectory
	var facX = 0;
	var facY = 0;
	for (i = 0; i < 1500; i++)
	{
		if(i < 125 || i >= 950)
		{
			facX += 0.05;
			facY += 0.05;
		}
		else if(i >= 125 && i < 220)
		{
			facX += 0.03;
			facY += 0.035;
		}
		else if(i >= 220 && i < 480)
		{
			facX += 0.06;
			facY += 0.03;
		}
		else if(i >= 480 && i < 630)
		{
			facX += 0.045;
			facY += 0.035;
		}
		else if(i >= 630 && i < 950)
		{
			facX += 0.02;
			facY += 0.045;
		}

		spritesPosX[i] = (320 - 64/2 + ((256 - 64 / 2 - 5.0) * Math.cos(facX)));
		spritesPosY[i] = (200 - 52/2 + 30 + ((128 - 52/2 - 10.0) * Math.sin(facY)));
	}

	go();
}

function showLogo()
{
	if(timeToShowLogo == 1)
	{
		alphaTime++;
		if(alphaTime == 10)
		{
			alpha += logoInc;
			if(alpha >= 1.0)
			{
				logoInc = -0.2;
				alpha = 1.0;
			}
			else if(alpha < 0.1)
			{
				logoInc = 0.2;
				alpha = 0.0000001;
				timeToShowLogo = 0;
			}
			alphaTime = 0;
		}
	}

	logocanvas.drawPart(mycanvas, 110,290, 0,0, 406,46, alpha, 0, 1.0, 1.0);
}

function morphSprite()
{
	if(frames % 10 == 0)
	{

		if(spritesFsm.current_state == "in_egg")
		{
			morphType = 7;

			sleepingTime++;
			if(sleepingTime == 60)
			{
				spritesFsm.process("awake");
				sleepingTime = 0;
			}
		}
		else if(spritesFsm.current_state == "morphing")
		{
			if(morphType > 0) morphType--;

			morphTime++;
			if(morphTime == 20)
			{
				spritesFsm.process("morph");
				morphTime = 0;
			}
		}
		else if(spritesFsm.current_state == "alive")
		{
			if(morphType == 0) aliveInc = 1;
			else if(morphType == 3) aliveInc = -1;
			morphType += aliveInc;

			aliveTime++;
			if(aliveTime == 70)
			{
				spritesFsm.process("deaden");
				aliveTime = 0;
			}
		}
		else if(spritesFsm.current_state == "demorphing")
		{
			if(morphType < 7) morphType++;

			demorphTime++;
			if(demorphTime == 20)
			{
				spritesFsm.process("demorph");
				demorphTime = 0;
			}
		}
	}
}

function drawRoad(road, y, i, band)
{
	if(road_offsets[i][band] != 0)
		road.drawPart(mycanvas, 0, y+road_sum[i][band], 0,road_sum[i][band], 640,road_offsets[i][band], 1.0, 0, 1.0, 1.0);
}

function go()
{
	mycanvas.fill('#000000');

	// show roads
	counter = (counter + 1) % 18;
	for(i=1; i<9; i+=2)
	{
		drawRoad(roadcanvas2, offset_y, counter, i);
	}
	for(i=0; i<9; i+=2)
	{
		drawRoad(roadcanvas1, offset_y, counter, i);
	}

	// display background images
	backtop.draw(mycanvas,0,0);
	backscroll.draw(mycanvas,0,400+(28*2)-79);

	// show equinox logo
	if(frames % 400 == 0) timeToShowLogo = 1;
	showLogo();

	// display sprites
	morphSprite();
	for (nbDragons = 0; nbDragons < 7; nbDragons++)
	{
		sprites[morphType].draw(mycanvas, spritesPosX[(tabpos+(nbDragons*18)) % 940], spritesPosY[ (tabpos+(18*nbDragons)) % 964]);

	}
	tabpos++;

	// display scrolltext
	scrolltext.draw(400+(28*2)-(26*2) - 2);

	//Debug
	//document.getElementById('pos').innerHTML="pos : " + tabpos;

	requestAnimFrame( go );
	frames++;
}

