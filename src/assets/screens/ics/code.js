
<*
REMAKE ICS INTRO OF THE GAME BUMPY'S! ORIGINAL CODE BY "EL PISTOLERO" - Music David Whittaker

ALL DONE USING CODEF FRAMEWORK AS USUAL, CODE BY AYOROS
SPECIAL THANX TO : NoNameNo, TotorMan, Sink, SoLO, MellowMan, Boss, ST Cooper, Stranger, Shazz, Jace....
HI TO ALL IMPACT MEMBBER : Toxic, Sunset and DAD
*/

var basepath = "screens/155/";

/*Music YM ou MOD*/
var player = new music("YM");

var myfond = new image(basepath +'fond.png') ;
var mylogo = new image(basepath +'ics.png') ;
var myraster = new image(basepath +'rast.png');
var myfont = new image(basepath +'font_noics.png');

var mycanvas;

/*Scroll texy*/
var myscrolltext;
var myfx;
var myfxparam=[
		{value: 1, amp: 80, inc:0.0016, offset: -0.028}
    ];

var mycanvas_scroll;
var mycanvas_anim;
var mycanvas_fond;
var vbl=0;
var pos_scroll=0;

function init(){

	mycanvas=new canvas(600,400,"main");
	mycanvas_fond=new canvas(600,330);
	mycanvas_anim=new canvas(600,330);
	mycanvas_scroll=new canvas(600,500);
	mycanvas_calc=new canvas(600*3,320*4);
	for(j=0;j<320*4;j+=117){
	  for(i=0;i<600*3;i+=116){
	    myfond.draw(mycanvas_calc,i,j);
	  }
	}
	mycanvas_calc.setmidhandle();
	mylogo.setmidhandle();

	myfont.initTile(32,32,32);
  myscrolltext = new scrolltext_horizontal();
	myscrolltext.scrtxt="    ICS PRESENTS YOU:         BUMPY'S     GAME CRACKED BY THE THREAT        ORIGINAL BY SLASH OF FRANCE       THIS INTRO WAS CODED, DESIGNED FOR I.C.S. BY  -EL PISTOLERO-..... (MANY THANKS!)     JUST AFTER THIS LITTLE INTRO YOU CAN READ A MESSAGE SENT TO SLASH BY SLEDGE, I THINK YOU'LL BE SURPRISED...           I WANT TO SAID A BIG HI TO  'NUKE' OUR NEW CRACKER, HE LIVES IN FRANCE LIKE A LOT OF MEMBERS OF ICS.      BIG HELLO TO SKINHEAD FROM GERMANY WHO GIVE US VERY HOT ORIGINALS (LIKE STONE AGE).      BIG HI TO SLASH AND BELGARION WHO ARE VERY GOOD/COOL GUYS!!!      AND OF COURSE I DON'T FORGET MR.FLY.        GREETINGS TO: SCSI, CYNIX, POMPEY PIRATES, DANNY FROM SINGAPORE, FUZION, THE REPLICANTS, AND YOU, IF YOU WANT!!!        WE LOOOKING FOR SUPPLIERS ALL OVER THE WORLD, IF YOU ARE INTRESTED WRITE TO THE P.O. BOX OR CALL ONE OF OUR BOARD.       THIS ALL FOR THIS TIME, SEE YOU SOON....              ";
	myscrolltext.init(mycanvas_scroll,myfont,0.3);
	myfx=new FX(mycanvas_scroll,mycanvas_anim,myfxparam);
	
	
	myAtariDecrunch = new AtariDecrunch(0, 30, 0, 100);
	init2();
}

	
function init2(){
    if ( myAtariDecrunch.finished == 1 ) {
      

        mycanvasblack=new canvas(600,400);
        mycanvasblack.fill('#0000000');
        mycanvas.fill('#000000') ;
        player.LoadAndRun(basepath + 'Leatherneck 1.ym');
      
        init3();
    } else {
        myAtariDecrunch.doDecrunch(mycanvas) ;
        requestAnimFrame( init2 );
    }
}


function init3(){
  mycanvas.fill('#000000') ;

  go();
}


function go(){

  mycanvas.fill('#000000') ;
  mycanvas_fond.clear();
  mycanvas_anim.clear();
  mycanvas_scroll.clear();
  
  for (var nbr_scr=0; nbr_scr<16; nbr_scr++) 
  {
    myscrolltext.draw(pos_scroll);
    pos_scroll=pos_scroll+32;
  }
  pos_scroll=0;
	
	myfx.siny(0,-85);
  mycanvas_anim.contex.globalCompositeOperation='source-in';
  myraster.draw(mycanvas_anim,0,0);
  mycanvas_anim.contex.globalCompositeOperation='source-over';
 
  mycanvas_anim.draw(mycanvas,0,0);
  mycanvas_calc.draw(mycanvas_fond,280-Math.sin((vbl*Math.PI)/200)*400,180-Math.cos((vbl*Math.PI)/200)*400) ;
  mycanvas_fond.draw(mycanvas,0,0)

  vbl++;

  mylogo.draw(mycanvas,300,370)
 
  requestAnimFrame( go );
}

