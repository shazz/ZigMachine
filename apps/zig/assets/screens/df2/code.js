// BIG THANKS to John Mindful, Supa Mike, Bradley Hudgens, and Jari Nikula for their help
// in putting this together! Who would have thought what appeared such a simple screen
// could be so tricky to get right?! :-)

var basepath = "screens/143/" ;

var player = new music("YM");
player.LoadAndRun(basepath + 'Renegade.ym');

var font=new image(basepath + 'fonts2.png');
var blue=new image(basepath + 'bluerasterback.png');

var mycanvas;
var scrollcanvas;
var mergecanvas;
var offscreencanvas;

var scrolltext;

var grad;
var gradcolor=
	[
	{color: 'rgb(0,0,255)' ,  offset:0},
	{color: 'rgb(0,192,0)', offset:0.2},
	{color: 'rgb(255,255,0)' ,  offset:0.4},
	{color: 'rgb(192,0,0)', offset:0.6},
	{color: 'rgb(255,255,0)' ,  offset:0.8},
	{color: 'rgb(0,192,0)' ,  offset:1}

	];

var x=0;

var y1=10;

var inc=8;

var text="      MELLOW MAN BRINGS YOU HIS REMAKE OF THE JINXSTER INTRO BY THE DELTAFORCE (OF THE UNION)... WRITTEN WITH CODEF!  ";
text+="     JINXSTER - CRACKED IN A WHOLE NIGHT BY CHAOS, INC. OF THE DELTAFORCE CRACKING GROUP! THIS VERSION RUNS IN ANY PATH!";
text+=" THIS INTRO WAS DESIGNED, CREATED, AND PROGRAMMED BY CHAOS, INC. GREETINGS GO TO : 42-CREW (HEY MARTIN, STILL TRYING TO";
text+=" CRACK DUNGEON MASTER?), TEX (WE ARE WAITING FOR YOUR B.I.G. DEMO!!), CSS (WHERE ARE YOU?!), PHIL/UK, DIV D, MR. ATARI,";
text+=" KILLER, B.O.S.S., DMA (NOTHING HEARD OF YOU GUYS! YOU OK?), TSUNOO, HCC.  INTERNAL GREETINGS TO : JOE COOL, QUESTLORD,";
text+=" NEW MODE, GREEN BERET CRACKER, AND ALL THE OTHER MEMBERS OF THE UNION!  YEP, YOU GOT IT, WE'RE AT THE END OF THE SCROLL";
text+="............ C YA!!   ";

function init(){
	mycanvas=new canvas(640,400,"main");
	offscreencanvas=new canvas(640,420);
	scrollcanvas=new canvas(640,64);
	mergecanvas=new canvas(640,420);

	grad=new grad(offscreencanvas,gradcolor);

	font.initTile(64,60,32);

	scrolltext = new scrolltext_horizontal();
	scrolltext.scrtxt=text;
	scrolltext.init(scrollcanvas,font,8);
	
	go();
}

function go(){
	mycanvas.fill('#000000');
	scrollcanvas.clear();
	mergecanvas.clear();

	blue.draw(mycanvas,x,0);

	grad.drawH();

	x-=5;

	if (x <= -640) x=0;    

	scrolltext.draw(0);	

	y1+=4;

	for (var i=-1;i<6;i++)
  		{
		scrollcanvas.drawPart(mergecanvas,0,y1+(i*(70)),0,0,640,60,1,0,1,1);
		}
	
	if (y1>=70) y1=0;
						
	mergecanvas.contex.globalCompositeOperation='source-atop';
	offscreencanvas.drawPart(mergecanvas, 0,0, 0,0, 640,420, 1.0, 0, 1.0, 1.0);

	mergecanvas.drawPart(mycanvas, 0,0, 0,0, 640,420, 1.0, 0, 1.0, 1.0);
	mergecanvas.contex.globalCompositeOperation='source-over';

	requestAnimFrame( go );
}
 
