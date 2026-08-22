<!DOCTYPE HTML>
<html> 
	<head> 
		<script src="http://codef.santo.fr/codef/codef_core.js"></script> 
		<script src="http://codef.santo.fr/codef/codef_scrolltext.js"></script>
		<script src="http://codef.santo.fr/codef/codef_fx.js"></script>
		<script src="http://codef.santo.fr/codef/codef_3d.js"></script>		
		<script src="http://codef.santo.fr/codef/codef_starfield.js"></script> 
		<script> 
			var mycanvas;
			var starfield;
			var scrolltext;
			var scrollcanvas;
			var mergecanvas;
			
			// 130 - 340
			var posBand1 = 130;
			var posBand2 = 130+151;
			var posBand3 = 130+151+151;
			
			var t3d;
			var tObj = new Array();
			var tObjVert = new Array();
			
			tObjVert=[
					// T
					{x:-100, 	y:0, 	z: 0},
					{x:   0, 	y:0, 	z: 0},
					{x:   0, 	y:-30, 	z: 0},
					{x: -32, 	y:-30, 	z: 0},
					{x:	-32, 	y:-120, z: 0},
					{x:	-68, 	y:-120, z: 0},
					{x:	-68, 	y:-30, 	z: 0},
					{x:	-100, 	y:-30, 	z: 0},
					{x:	-100, 	y:0, 	z: 0},
					// C
					{x:  20, 	y:0, 	z: 0},
					{x: 120, 	y:0, 	z: 0},
					{x: 120, 	y:-30, 	z: 0},
					{x:  52, 	y:-30, 	z: 0},
					{x:	 52, 	y:-90, 	z: 0},
					{x:	120, 	y:-90, 	z: 0},
					{x:	120, 	y:-120,	z: 0},
					{x:	 20, 	y:-120,	z: 0},
					{x:	 20, 	y:0, 	z: 0},
					// B
					{x: 140, 	y:0, 	z: 0},
					{x: 210, 	y:0, 	z: 0},
					{x: 240, 	y:-30, 	z: 0},
					{x: 210, 	y:-60, 	z: 0},
					{x:	240, 	y:-90,	z: 0},
					{x:	210, 	y:-120,	z: 0},
					{x:	140, 	y:-120,	z: 0},
				   ];
			
			tObj=[
					// T
					{p1:0, p2:1},
					{p1:1, p2:2},
					{p1:2, p2:3},
					{p1:3, p2:4},
					{p1:4, p2:5},
					{p1:5, p2:6},
					{p1:6, p2:7},
					{p1:7, p2:8},
					{p1:8, p2:0},
					// C
					{p1:0+9, p2:1+9},
					{p1:1+9, p2:2+9},
					{p1:2+9, p2:3+9},
					{p1:3+9, p2:4+9},
					{p1:4+9, p2:5+9},
					{p1:5+9, p2:6+9},
					{p1:6+9, p2:7+9},
					{p1:7+9, p2:0+9},
					// B
					{p1:0+9+9, p2:1+9+9},
					{p1:1+9+9, p2:2+9+9},
					{p1:2+9+9, p2:3+9+9},
					{p1:3+9+9, p2:4+9+9},
					{p1:4+9+9, p2:5+9+9},
					{p1:5+9+9, p2:6+9+9},
					{p1:6+9+9, p2:0+9+9},
				 ];
			
			
			var font = new image('screens/021/fonts.png');
			
			var rasters = new image('screens/021/backrasterband.png');
			var rasterscanvas;
			
			var scrollfx;
			var scrollfxparam=[
					{value: 10, amp: 80, inc:0.002, offset: -0.03	},
			];
			
			var my2dstarsparams=[
				{nb:280, speedy:0, speedx:6, color:'#BBBBBB', size:1},
			];
			
			var text = "    YO YO   -AN COOL- IS BACK TO BURN WITH A NEW CRACK........ AND THE NEW CRACK IS               THE GAMES......    THIS TIME -MEGA CRIBB- FROM -1 LIFE CREW- SITS BY MY SIDE AND EATS CANDY   THE INTRO IS MADE BY: -AN COOL- AND THE CRACKING IS MADE BY: -AN COOL- AND -MEGA CRIBB-          BELIVE IT OR NOT, THE MUSAXX IS MADE BY: -AN COOL-           THIS GAME IS THE BEST SPORT-GAME I'VE SEEN ON THE ATARI ST AND I HOPE YOU WILL HAVE A GREAT TIME PLAYING IT.          I'VE BEEN OF THE CRACKING MARKET FOR A WHILE, BUT IT'S BECAUSE OF THE NEW DEMO (SOWHAT) WE ARE CODING. THE DEMO WILL CONTAIN ABOUT 10 SCREENS AND ALMOST ALL IS GOOD (I THINK)...   YOU WILL SEE MORE 2D-OBJECTS AND MORE COMPLEX 2D-OBJECTS IN THE DEMO-LOADER. THE DEMO SHOULD HAVE BEEN RELEASED AT OUR COPYPARTY THE 3-6 AUG. BUT AS ALWAYS........  YEAH, YOU KNOW??????.........        A HELLO GOES TO NICK OF TCB (HE WORKS AS A SECRET AGENT FOR KREML NOW)  AND SNAKE THE  LITTLE YELLOW BIRD OF REPLICANTS.......        OK.  I THINK THAT THAT WAS ALL FOR THIS TIME....................."
						

			function init(){
				mycanvas=new canvas(640,400,"main");
				rasterscanvas = new canvas(640,400);
				
				font.initTile(64,34,32);
				
				scrollcanvas = new canvas(640,100);
				mergecanvas  = new canvas(640,400);
				
				scrolltext = new scrolltext_horizontal();
				scrolltext.scrtxt=text;
				scrolltext.init(scrollcanvas,font,6);
				scrollfx=new FX(scrollcanvas,mergecanvas,scrollfxparam);
				
				starfield=new starfield2D_dot(mycanvas, my2dstarsparams); //280, 6, 640,400, 320, 200,'#BBBBBB', 40,0,0,1);
				
				//camZ, fov, near, far
				t3d=new codef3D(mycanvas, 1350, 40, 200, 1800 );
				
				
				for(i=0;i<25;i++)
				{
					tObjVert[i].x -= 0;
					tObjVert[i].z += 250;
					tObjVert[i].y += 120;
				}
					
				for(i=9;i<17;i++)
				{
					tObjVert[i].x -= 50;
					tObjVert[i].z -= 50;
					tObjVert[i].y -= 0;
				}
			
				for(i=17;i<25;i++)
				{
					tObjVert[i].x -= 100;
					tObjVert[i].z -= 100;
					tObjVert[i].y -= 0;
				}
				t3d.lines(tObjVert, tObj, new LineBasicMaterial({ color: 0xFF0000, linewidth:2}));
				go();
			}

			function go(){
				mycanvas.fill('#000000');
				scrollcanvas.clear();
				mergecanvas.clear();
			
				// draw 3D dot starfield
				starfield.draw();
			
				// logo 3D rotation
				t3d.group.rotation.x+=0.06;
				t3d.group.rotation.y+=0.07;
				t3d.group.rotation.z+=0.04;
				t3d.draw();
			
				// draw rasters back scroller
				posBand1 -=3;	if(posBand1 <= (130-151)) posBand1 = 130+151+151;
				posBand2 -=3;	if(posBand2 <= (130-151)) posBand2 = 130+151+151;
				posBand3 -=3;	if(posBand3 <= (130-151)) posBand3 = 130+151+151;
				rasters.draw(rasterscanvas,0, posBand1);
				rasters.draw(rasterscanvas,0, posBand2);
				rasters.draw(rasterscanvas,0, posBand3);
			
				// draw scrolltext offscreen
				scrolltext.draw(0);
				scrollfx.siny(0,260);
			
				// draw raster scroll inside scrolltext using source-atop
				mergecanvas.contex.globalCompositeOperation='source-atop';
				rasterscanvas.drawPart(mergecanvas, 0,0, 0,0, 640,400, 1.0, 0, 1.0, 1.0);
			
				// draw resulting buffer on screen canvas
				mergecanvas.drawPart(mycanvas, 0,-70, 0,00, 640,400, 1.0, 0, 1.0, 1.0);
				mergecanvas.contex.globalCompositeOperation='source-over';

				requestAnimFrame( go );
			}
 
		</script> 
	</head> 
	<body onLoad="init();">
		<center><div id="main"></div></center>
	</body> 
</html>