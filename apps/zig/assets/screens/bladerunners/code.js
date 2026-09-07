var player = new music("YM");
//player.stereo(true);
player.LoadAndRun('screens/037/rampage.ym');

var mybg=new image('screens/037/bg.png');
var myfont = new image('screens/037/fontok.png');
var myrfont = new image('screens/037/rfont.png');

var mycanvas;
var myscrolltext;

function init(){
	mycanvas=new canvas(768,398,"main");
	myscroll=new canvas(640,64);
	myscroll2=new canvas(640,64*7);
	myrfontcanvas=new canvas(640,398);
	myrfontcanvas.contex.drawImage(myrfont.img,0,0,14,398,0,0,640,398);



  myfont.initTile(64,64,32);
	myscrolltext = new scrolltext_horizontal();
	myscrolltext.scrtxt="WELCOME TO 'DUNGEON MASTER' -- CRACKED BY THE cdefghijkl -- THIS GAME IS CRACKED FOR  THE BLADE RUNNERS  - THE ULTIMATE CRACKER CREW...HELLO BOSS,TEX,CSS,TNT-CREW,MMC,BXC,TSUNOO,1001-CREW,AND OF COURSE YOU......DUNGEON MASTER WAS A VERY GOOD PROTECTED GAME THAT TOOK A LONG TIME TO CRACK. SO IF YOU ARE REQUESTED TO PUT IN THE DUNGEON MASTER DISK JUST IGNORE THAT MESSAGE AND CONTINUE (PRESSING THE RETURN KEY) YOUR GAME...THANKS TO MMC FOR THE ORIGINAL THAT WAS AFTERWARDS NEARLY UNREADABLE! TO CHANGE THE TUNE TOGGLE WITH F1/F2 SO YOU WILL LISTEN TO BOTH OF THE RAMPAGE MUSIC PIECES AGAIN COMPOSED BY WHITTIE-BABY!...";
	myscrolltext.init(myscroll,myfont,2);
	go();
}

var rposy=0;
var ssin=0;

function go(){
	mycanvas.fill('#000000');
	mycanvas.contex.drawImage(mybg.img,0,0,10,510,0,rposy%102,768,510);
	rposy-=1.2;

	myscroll.clear();
	myscrolltext.draw(0);

	myscroll2.clear();
	for(var i=-32;i<7*64;i+=64){
	  myscroll.draw(myscroll2,0,i+Math.sin(ssin)*10);
	}
	ssin+=0.06;
	myscroll2.contex.globalCompositeOperation='source-in';
	myrfontcanvas.draw(myscroll2,0,0);
	myscroll2.contex.globalCompositeOperation='source-over';

	myscroll2.draw(mycanvas,64,0);

	requestAnimFrame( go );
}

