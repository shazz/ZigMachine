var player = new music("YM");
player.stereo(true);

var mycanvas;
var my3d;
	
var myfont = new image("screens/124/font.png");


	
var myobj0 = new Array();
var myobjvert0 = new Array();
myobjvert0=[
        {x: -2, y: -2, z: 0},
        {x: 240, y:  -2, z: 0},
        {x:240, y:  60, z: 0},
        {x:-2, y: 60, z: 0},
];
myobj0=[ 
        {p1:0, p2:1},
        {p1:1, p2:2},
        {p1:2, p2:3},
		{p1:3, p2:0},
];
	
var myobj1 = new Array();
var myobjvert1 = new Array();
myobjvert1=[
        {x: 0, y: 58, z: -10},
        {x: 0, y:  0, z: -10},
        {x:40, y:  0, z: -30},
        {x:40, y: 30, z: -30},
        {x: 9, y: 30, z: -13},
        {x: 20, y: 30, z: -19},
		{x: 40, y:  58, z: -30},
	
		{x: 45, y: 58, z: -10},
		{x: 45, y: 0, z: -10},
		{x: 85, y: 0, z: -30},
		{x: 85, y: 30, z: -30},
		{x: 54, y: 30, z: -13},
	
		{x: 97-13, y: 0, z: -10},
		{x: 120-13, y: 0, z: -20},
		{x: 110-13, y: 0, z: -15.5},
		{x: 110-13, y: 58, z: -15.5},
		{x: 97-13, y: 58, z: -10},
		{x: 120-13, y: 58, z: -20},
	
		{x: 133-10, y: 58, z: -10},
		{x: 153-10, y: 0, z: -15},
		{x: 173-10, y: 58, z: -30},
		{x: 143-10, y: 30, z: -12.5},
		{x: 163-10, y: 30, z: -22.5},
	
		{x: 181, y: 0, z: -10},
		{x: 214, y: 0, z: -30},
		{x: 198, y: 0, z: -20.5},
		{x: 198, y: 58, z: -20.5},
       ];
myobj1=[ 
        {p1:0, p2:1},
        {p1:1, p2:2},
        {p1:2, p2:3},
        {p1:3, p2:4},
		{p1:5, p2:6},
	
		{p1:7, p2:8},
		{p1:8, p2:9},
		{p1:9, p2:10},
		{p1:10, p2:11},
	
		{p1:12, p2:13},
		{p1:14, p2:15},
		{p1:16, p2:17},
	
		{p1:18, p2:19},
		{p1:19, p2:20},
		{p1:21, p2:22},

		{p1:23, p2:24},
		{p1:25, p2:26},
      ];

var myobj2 = new Array();
var myobjvert2 = new Array();
myobjvert2=[
        {x: 60, y: 58, z: -30},
        {x: 20, y: 58, z: -10},
        {x: 20, y:  0, z: -10},
        {x: 60, y:  0, z: -30},
        {x: 20, y: 30, z: -10},
		{x: 50, y: 30, z: -25},
	
	    {x: 105, y:58, z: -30},
        {x: 65, y: 58, z: -10},
		{x: 65, y:  0, z: -10},
	
		{x: 148, y:58, z: -30},
        {x: 110, y: 58, z: -10},
		{x: 110, y:  0, z: -10},
		{x: 148, y:  0, z: -30},
	
		{x: 153, y:58, z: -10},
        {x: 153, y: 0, z: -10},
		{x: 193, y:  58, z: -30},
		{x: 193, y:  0, z: -30},
	
		{x: 198, y:58, z: -10},
        {x: 238, y: 58, z: -30},
		{x: 238, y:  30, z: -30},
		{x: 198, y:  30, z: -10},
		{x: 198, y:  0, z: -10},
		{x: 238, y:  0, z: -30},	
];	
myobj2=[ 
        {p1:0, p2:1},
        {p1:1, p2:2},
        {p1:2, p2:3},
        {p1:4, p2:5},
	
		{p1:6, p2:7},
		{p1:7, p2:8},
	
		{p1:9, p2:10},
		{p1:10, p2:11},
	    {p1:11, p2:12},
	
		{p1:13, p2:14},
		{p1:14, p2:15},
	    {p1:15, p2:16},
	
		{p1:17, p2:18},
		{p1:18, p2:19},
	    {p1:19, p2:20},
		{p1:20, p2:21},
		{p1:21, p2:22},
];	
	
function init(){
	mycanvas=new canvas(768,540,"main");
	myAtariDecrunch = new AtariDecrunch(0, 30, 0, 300)
	init2()
}
	
function init2(){
    if ( myAtariDecrunch.finished == 1 ) {
        player.LoadAndRun('screens/124/Decade 3D Dots.ym');
        init3() ;
    } else {
        myAtariDecrunch.doDecrunch(mycanvas) ;
        requestAnimFrame( init2 );
    }
}
	
function init3(){
	myfont.initTile(16,16,32);
	my3d=new codef3D(mycanvas, 800, 20, 1, 1000 );
		for(var i=0;i<myobjvert0.length;i++){
		myobjvert0[i].y-=30;
		myobjvert0[i].x-=120;
	}
	for(var i=0;i<myobjvert1.length;i++){
		myobjvert1[i].y-=30;
		myobjvert1[i].x-=120;
	}
	for(var i=0;i<myobjvert2.length;i++){
		myobjvert2[i].y-=30;
		myobjvert2[i].x-=120;
	}
	my3d.lines(myobjvert0, myobj0, new LineBasicMaterial({ color: 0xf01010, linewidth:2}));
	my3d.lines(myobjvert1, myobj1, new LineBasicMaterial({ color: 0xf0f010, linewidth:2}));
	my3d.lines(myobjvert2, myobj2, new LineBasicMaterial({ color: 0xf0f0f0, linewidth:2}));
	
	myback=new canvas(40*16,34*16);
	myfont.print(myback,"****************************************",0,0*16);
	myfont.print(myback," **   THE REPLICANTS AND ST AMIGOS   ** ",0,1*16);
	myfont.print(myback,"    **   BRING YOU AN HOT STUFF   **    ",0,2*16);
	myfont.print(myback,"       **************************       ",0,3*16);
	
	myfont.print(myback,"   SAVAGELY BROKEN AN TRAINED BY MAXI",0,5*16);
	myfont.print(myback,"  ------------------------------------",0,6*16);
	myfont.print(myback,"  DIS BOOT WAS ALSO FAST CODED BY MAXI",0,7*16);
	myfont.print(myback," --------------------------------------",0,8*16);
	
	myfont.print(myback,"       COPY IN 2 SIDES 10 SECTORS",0,10*16);
	myfont.print(myback,"   THE MAGIC KEY FOR THE TRAINER IS *",0,11*16);
	myfont.print(myback,"SORRY FOR DIS LITTLE LAME CODE ,COZ THAT",0,12*16);
	myfont.print(myback,"IS NOT MY BEST 3D LINE ROUT ,SO FAR NOT.",0,13*16);
	myfont.print(myback,"THAT IS MY SHORTER ONE ! BUT IN 3 PLANES",0,14*16);
	myfont.print(myback,"THE GOOD IS RATHER MY UPPER BORDER ROUT!",0,15*16);
	
	
	myfont.print(myback,"VERY SPECIAL REGARDS GO TO :",0,19*16);
	myfont.print(myback," THOR - AVB - ST WAIKIKI- MINIMAX - ZAE",0,20*16);
	myfont.print(myback," MAD VISION  - FUZION - LITTLESWAP -FOF",0,21*16);
	myfont.print(myback,"  BAD BOYS - MCA - ACB - THE REDUCTORS",0,22*16);
	myfont.print(myback,"  RCA AND ALL THE MEMBERS OF THE UNION",0,23*16);
	
	myfont.print(myback,"I SEND THE NORMAL GREETINGS TO :",0,25*16);
	myfont.print(myback," ST CONNEXION-IMAGINA-PHALANC-FF-TELLER",0,26*16);
	myfont.print(myback," 2 LIVE CREW-PENDRAGONS-DRAGON-FRAISINE",0,27*16);
	myfont.print(myback," DIMITRI-EQUINOX-TGE-SEWER SOFT-ACF-BMT",0,28*16);
	myfont.print(myback," MEDWAY BOYS-OVR-MCS-TDA-LOST BOYS-NEXT",0,29*16);
	myfont.print(myback," ULM-PARADOX-SYNC-OMEGA-INNER CIRCLE-MU",0,30*16);
	
	myfont.print(myback,"ENJOY THE VIOLENCE..THE REPLICANTS RULEZ",0,32*16);
	myfont.print(myback,"****************************************",0,33*16);
	
	go();
}
var posx=0;
function go(){
	mycanvas.fill('#000000');
	myback.draw(mycanvas,64,0);
	my3d.group.rotation.x+=0.01;
	my3d.group.rotation.y+=0.02;
	my3d.group.rotation.z+=0.04;
	
	my3d.group.position.x=Math.sin(posx)*70;
	
	
	posx+=0.05;
	
	my3d.draw();
	requestAnimFrame( go );
}
 
