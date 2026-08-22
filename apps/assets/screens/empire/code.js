var myfont = new image('screens/024/fonts2.png');
var mycanvas;
var myscrolltext;

var my2dstarfield;
var my2dstarsparams=[
		{nb:50, speedy:0, speedx:-7, color:'#F0F0F0', size:2, minY:70, maxY:400-70}, //A0A0A0
		{nb:50, speedy:0, speedx:-4, color:'#A0A0A0', size:2, minY:70, maxY:400-70},
		{nb:50, speedy:0, speedx:-2, color:'#606060', size:2, minY:70, maxY:400-70},
              ];

var t3d;
var tObj = new Array();
var tObjVert = new Array();

tObjVert=[
        // E
        {x:   0, 	y:0, 	z: 0},
        {x:  10, 	y:0, 	z: 0},
        {x:  10, 	y:-5, 	z: 0},
        {x:   0, 	y:-5, 	z: 0},
        {x:	  0, 	y:-10,  z: 0},
        {x:	 10, 	y:-10, 	z: 0},
        // M
        {x:  12, 	y:-10, 	z: 0},
        {x:  12, 	y:0, 	z: 0},
        {x:  17, 	y:0, 	z: 0},
        {x:  17, 	y:-10, 	z: 0},
        {x:	 20, 	y: 0, 	z: 0},
        {x:	 22, 	y:-2, 	z: 0},
        {x:	 22, 	y:-10,	z: 0},
        // P
        {x:  24, 	y:-10, 	z: 0},
        {x:  24, 	y:0, 	z: 0},
        {x:  32, 	y:0, 	z: 0},
        {x:  34, 	y:-2, 	z: 0},
        {x:	 34, 	y:-5,	z: 0},
        {x:	 24, 	y:-5,	z: 0},
		// I
		{x:	 36, 	y:0,	z: 0},
		{x:	 36, 	y:-10,	z: 0},
		// R
        {x:  38, 	y:-10, 	z: 0},
        {x:  38, 	y:0, 	z: 0},
        {x:  46, 	y:0, 	z: 0},
        {x:  48, 	y:-2, 	z: 0},
        {x:	 48, 	y:-5,	z: 0},
        {x:	 38, 	y:-5,	z: 0},
        {x:	 44, 	y:-5,	z: 0},
        {x:	 48, 	y:-10,	z: 0},
		// E
        {x:  50, 	y:0, 	z: 0},
        {x:  60, 	y:0, 	z: 0},
        {x:  60, 	y:-5, 	z: 0},
        {x:  50, 	y:-5, 	z: 0},
        {x:	 50, 	y:-10,  z: 0},
        {x:	 60, 	y:-10, 	z: 0},
       ];

tObj=[
		// E
        {p1:0, p2:1},
        {p1:2, p2:3},
        {p1:3, p2:4},
        {p1:4, p2:5},
        // M
        {p1:6, p2:7},
        {p1:7, p2:8},
        {p1:8, p2:9},
        {p1:8, p2:10},
        {p1:10, p2:11},
        {p1:11, p2:12},
        // P
        {p1:13, p2:14},
        {p1:14, p2:15},
        {p1:15, p2:16},
        {p1:16, p2:17},
        {p1:17, p2:18},
        // I
        {p1:19, p2:20},
        // R
        {p1:21, p2:22},
        {p1:22, p2:23},
        {p1:23, p2:24},
        {p1:24, p2:25},
        {p1:25, p2:26},
        {p1:26, p2:27},
        {p1:27, p2:28},
		// E
        {p1:29, p2:30},
        {p1:31, p2:32},
        {p1:32, p2:33},
        {p1:33, p2:34},
     ];

var player = new music("YM");

function starfield2D_range_dot(dst,params){
	this.dst=dst;
	this.stars=new Array();
	var t=0;

	for(var i=0; i<params.length; i++){
		for(var j=0; j<params[i].nb; j++){
			this.stars[t]={x:Math.random()*this.dst.canvas.width, y:params[i].minY + Math.random()*(params[i].maxY - params[i].minY), speedx:params[i].speedx, speedy:params[i].speedy, color:params[i].color, size:params[i].size};
			t++;
		}
	}

	this.draw=function(){
		for(var i=0; i<this.stars.length; i++){
			this.dst.plot(this.stars[i].x,this.stars[i].y,this.stars[i].size,this.stars[i].color);
			this.stars[i].x+=this.stars[i].speedx;
			this.stars[i].y+=this.stars[i].speedy;
			if(this.stars[i].x>this.dst.canvas.width) this.stars[i].x=0;
			if(this.stars[i].x<0) this.stars[i].x=this.dst.canvas.width;
			if(this.stars[i].y>this.dst.canvas.height) this.stars[i].y=0;
			if(this.stars[i].y<0) this.stars[i].y=this.dst.canvas.height;
		}
	}

}

function init()
{
	player.LoadAndRun('screens/024/Leaving Teramis 10.ym');

	mycanvas=new canvas(640,400,"main");
	my2dstarfield=new starfield2D_range_dot(mycanvas,my2dstarsparams);

	myfont.initTile(64,65,32);
	myscrolltext = new scrolltext_horizontal();
	myscrolltext.scrtxt="THE EMPIRE PRESENTS A NEW LITTLE INTRO FROM THE FALLEN ANGELS. CODE BY STEF, FONTS BY STARFIX, AND MUSEXX BY JOCHEN HIPPEL. THE GREETINGS GO TO: ST-CONNEXION, TECHNOCRATS AND....   AND....   ZE WATSIT.      OK, THAT'S ALL FOLKS!      BYE FREAKS.....";
	myscrolltext.init(mycanvas,myfont,3.5); //3.5

	for(i=0;i<35;i++)
	{
		tObjVert[i].x -= 30;
		tObjVert[i].y += 5;
	}


	//camZ, fov, near, far
	t3d=new codef3D(mycanvas, 90, 40, 20, 1800 );
	t3d.lines(tObjVert, tObj, new LineBasicMaterial({ color: 0xE0E0E0, linewidth:2}));
	t3d.group.eulerOrder="YXZ";



	go();
}

function go(){
	mycanvas.fill('#000000');
	my2dstarfield.draw();

	// logo 3D rotation
	t3d.group.rotation.y +=0.0415;
	t3d.group.rotation.x +=0.0415;

	t3d.draw();

	myscrolltext.draw(400-64);
	myscrolltext.draw(1);

	requestAnimFrame( go );
}
