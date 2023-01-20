
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
<script src="//codef.santo.fr/codef/codef_core.js"></script>
<script src="//codef.santo.fr/codef/codef_scrolltext.js"></script>
<script src="//codef.santo.fr/codef/codef_starfield.js"></script>
<script src="//codef.santo.fr/codef/codef_3d.js"></script>

<script> 
var basepath = "screens/543/";
var ctrLoaded = 0, elemsToLoad = 5, font, balls, back, ballFont, bigFont, scrollCan, ctr=0, ctrColor=0, colors=[],
    starf, starfCan, can3D, tween3D, rotation, effets = {x:0}, color = {x:0, c:0}, colorIdx = 0, design;
const couleurs = "00E.02E.04E.06E.08E.0AE.0CE.0EE.0EC.0EA.0E8.0E6.0E4.0E2.0E0.2E0.4E0.6E0.8E0.AE0.CE0.EE0.EC0.EA0.E80.E60.E40.E20.E00.E02.E04.E06.E08.E0A.E0C.E0E.C0E.A0E.80E.60E.40E.20E".split(".");

font = new image(basepath + "Ikari_font_8x7.png");
font.img.onload = countLoaded;
balls = new image(basepath + "balls.png");
balls.img.onload = countLoaded;
back = new image(basepath + "fond.png");
back.img.onload = countLoaded;

loadScript(basepath + 'objects.js').then(countLoaded);
loadScript(basepath + 'gsap.min.js').then(countLoaded);

// SNDH Player
loadScript(basepath + 'scriptprocessor_player.js')
.then(()=> loadScript(basepath + 'backend_sc68.js'))
.then(()=> loadScript(basepath + 'sndh-player.js'))
.then(countLoaded)
.catch((url) => console.log('Failed to load script ' + url));

function init(){
  mainCanvas = new canvas(640,400,"main");
  scrollCan = new canvas(640,128);
  starfCan = new canvas(640,640);
  starfCan.setmidhandle();
  ctx = mainCanvas.contex;
  document.getElementById('main').style.backgroundColor = '#000';
  
  couleurs.forEach((c)=>{c='#'+c; colors.push(c); colors.push(c)});
  starf = new starfield3D(starfCan, 100, 2, 640,640, 320, 320,'#FFFFFF', 100,0,0);
  
  Object.keys(objets).forEach(nom => {
    objets[nom].vertices = objets[nom].vertices.map(k=>{k.x/=100;k.y/=100;k.z/=100; return k});
  });
  can3D = new codef3D(mainCanvas, 20, 20, 1, 200  );
  can3D.lines(objets['ancool'].vertices, objets['ancool'].lines, new LineBasicMaterial({ color: 0xFF0000, linewidth:2}));
  can3D.camera.scale.z = 2;
  setRotation('none');
  
  countLoaded();
}

function countLoaded(){
  if(++ctrLoaded > elemsToLoad)
    afterLoad();
}

function afterLoad(){
  var c,d,x,y,i;
  ballFont = new canvas(font.img.width*16, font.img.height*16);
  c = ballFont.contex;
  c.drawImage(font.img,0,0);
  d = c.getImageData(0,0,font.img.width, font.img.height);
  d=d.data;
    
  ballFont.clear();
  for(i=0,y=0; y<font.img.height; y++){
    for(x=0; x<font.img.width; x++){
      if(d[i] == 0){
        c.drawImage(balls.img, 0,0,16,16, x*16,y*16,16,16);
      }else{
        c.drawImage(balls.img, 16,0,16,16, x*16,y*16,16,16);
      }
      i+=4;
    }
  }
  
  bigFont = new image(ballFont.canvas.toDataURL('image/png'));
  bigFont.initTile(128,112,32);
  scrolltext = new scrolltext_horizontal();
  scrolltext.scrtxt = "             YO! DIS IS -AN COOL-..... ONCE AGAIN BACK WITH 3D GRAFIXX....... WELL IT'S NOTHING ADVANCED BUT IT'S 3D-VECTORS CREDITS....... CODE -AN COOL-...... OBJECTS......... -AN COOL- MUSIC........ MAD MAX..... NICE TUNE THIS LITTLE SCREEN IS MADE FOR THE..... REPLICANTS CRACKS...... I HEARD THAT PEOPLE ARE SAYING -TCB- ARE JUST SPREADING ROUMORS ABOUT THEIR NEW DEMO SO WE WILL REMEMBER THEM...... BOY!!!!!!!!!!!!! THOSE GUYS WILL SOOOOON BE SOOOO SORRY THE NEW DEMO FROM TCB IS YET TO COME.... OK..... HOMEBOYGREETINGS.. MEGA CRIBB... NICK. TANIS. JAS. MAD BUTCHER. NORDIC CODERS AND LYNX.............. NOTHING MORE TO WRITE ABOUT NO NEW DEMOS... NO NEW GAMES THAT ARE GOOD...... NOTHING ABOUT NEW TRICKS... SO THE ONLY THING I CAN SAY IS...... TRY TO GET HOLD OF MY NEW CART..... THE EXPLORER IT'S UNSTOPPABLE...... AND SEEYA";
  scrolltext.init(scrollCan, bigFont, 16);
  for(i=0;i<50;i++)  scrolltext.draw(0);
  
  // Background animation
  tweenColor = gsap.timeline({repeat: -1})
    .fromTo(color, {x:-1}, {duration:6, x:1})
    .to(color, 0.5, {c:255})
    .to(color, 0.5, {c:0})
    .fromTo(color, {x:-1}, {duration:6, x:1})
    .to(color, 0.2, {c:255})
    .to(color, 0.2, {c:128})
    .to(color, 0.2, {c:255})
    .to(color, 0.2, {c:128})
    .to(color, 0.2, {c:255})
    .to(color, 0.2, {c:128})
    .to(color, 0.2, {c:255})
    .to(color, 0.2, {c:128})
    .to(color, 0.2, {c:255})
    .to(color, 0.5, {c:0})
    .call(changeColor)
  ;

  // 3D Animations
  tween3D = gsap.timeline({onComplete:()=>{tween3D.seek('ici')}});
  tween3D.to(can3D.camera.scale, 2, {z:0.2})
    .addLabel('ici')
    .call(changeObject, ['6faces'])
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 5, {z:2})
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})

    .call(changeObject, ['vaisseau'])
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 5, {z:2})
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})

    .call(changeObject, ['tv'])
    .call(setRotation, ['none'])
    .to(can3D.camera.scale, 2, {z:2})
    .call(setRotation, ['fast'])
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})

    .call(changeObject, ['pyramide'])
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 5, {z:2})
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})

    .call(changeObject, ['tcb'])
    .call(setRotation, ['none'])
    .to(can3D.camera.scale, 2, {z:2})
    .call(setRotation, ['fast'])
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})

    .call(changeObject, ['union'])
    .call(setRotation, ['none'])
    .to(can3D.camera.scale, 2, {z:2})
    .call(setRotation, ['fast'])
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})

    .call(changeObject, ['disk'])
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 5, {z:2})
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})

    .call(changeObject, ['ancool'])
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 5, {z:2})
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})

    .call(changeObject, ['cone'])
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 5, {z:2})
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})

    .call(changeObject, ['man'])
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 5, {z:2})
    .fromTo(effets, {x:-1}, {duration:30,x:1})
    .call(setRotation, ['slow'])
    .fromTo(effets, {x:-1}, {duration:2,x:1})
    .call(setRotation, ['fast'])
    .to(can3D.camera.scale, 2, {z:0.2})
  ;
  
  soundchip = new SndhPlayer(basepath + 'The_Lost_Boys.sndh');  
  requestAnimFrame(go);
}

function go(){
  mainCanvas.clear();
  ctr++;
  fond();
  etoiles();
  redLines();
  texte();
  requestAnimFrame(go);
}

function changeColor(){
  colorIdx = Math.floor(3*Math.random());
}

function fond(){
  if(color.c == 0)
    return;
  ctx.drawImage(back.img, 0, 0);
  ctx.globalCompositeOperation = 'source-in';
  switch(colorIdx){
    case 0 :
      ctx.fillStyle = "rgba(0,0," + color.c + ")";
      break;
    case 1 :
      ctx.fillStyle = "rgba(" + color.c + "," + color.c + "," + color.c + ")";
      break;
    case 2 :
      ctx.fillStyle = "rgba(" + color.c + ",0,0)";
      break;
  }
  ctx.fillRect(0,0,640,400);
  ctx.globalCompositeOperation = 'source-over';
}

function changeObject(nom){
  can3D.scene.remove(can3D.group);
  can3D.group = new THREE.Object3D();
  can3D.scene.add(can3D.group);
  can3D.lines(objets[nom].vertices, objets[nom].lines, new LineBasicMaterial({ color: 0xFF0000, linewidth:2}));
  can3D.camera.scale.z = 0.2;
}

function setRotation(nom){
  rotation = rotations[nom];
}

function redLines(){
  can3D.group.rotation.x += rotation.x;
  can3D.group.rotation.y += rotation.y;
  can3D.group.rotation.z += rotation.z;
  can3D.draw();
}

function etoiles(){
  starfCan.clear();
  starf.draw();
  starfCan.draw(mainCanvas,320,200,1,-ctr/3);
}
  
function texte(){
  var imgd,d,i,k;
  scrollCan.fill("#000");
  scrolltext.draw(0);
  // Colors
  if((ctr & 3) == 0){
    ctrColor++;
    if(ctrColor >= colors.length)
      ctrColor = 0;
  }
  scrollCan.contex.globalCompositeOperation = "multiply";
  for(i=0,k=ctrColor;i<8;i++,k++){
    if(k>=colors.length)
      k=0;
    scrollCan.contex.fillStyle = colors[k];
    scrollCan.contex.fillRect(0,i*16,640,16);
  }
  scrollCan.contex.globalCompositeOperation = "source-over";  
  
  // Gestion de la transparence
  imgd = scrollCan.contex.getImageData(0,0,640,128);
  d = imgd.data;
  for(i=0; i<d.length; i+=4)
    if(d[i]==0 && d[i+1]==0 && d[i+2] == 0)
      d[i+3] = 0;
  scrollCan.contex.putImageData(imgd,0,0);
  
  scrollCan.draw(mainCanvas,0, ~~(150+120*Math.sin(ctr/18)));  

}
  
function loadScript(url){
  return new Promise((resolve, reject) => {
    let elem = document.createElement('script');
    elem.src = url;
    document.head.appendChild(elem);
    elem.onload = () => resolve(url);
    elem.onerror = () => reject(url);
  });
}
</script>
<script>
	function initHack(){
		audioCtx = new AudioContext();
		setTimeout(function () {initHack2();}, 500);
	}
	function initHack2(){
		if(audioCtx.state === "running"){
	        	audioCtx = undefined; // unset
        		delete(audioCtx); //
			if(document.getElementById("fsbut")){
				document.getElementById("fsbut").setAttribute('style', 'display: block');
			}
	        	init();
    		}
		else{
			var oImg = document.createElement("img");
			oImg.setAttribute('src', 'clickhere2.png');
			//oImg.setAttribute('width', '100px');
			oImg.setAttribute('onclick','AudioHack();');
			document.getElementById("main").appendChild(oImg);
		}
	}

	function AudioHack(){
        	document.getElementById("main").removeChild(document.getElementById("main").lastChild);
		if(typeof CODEF_AUDIO_CONTEXT !== 'undefined' && CODEF_AUDIO_CONTEXT !== null)
			CODEF_AUDIO_CONTEXT.resume();
		if(typeof window.neoart !== 'undefined') 
			if(typeof window.neoart.audioContext !== 'undefined') 
				window.neoart.audioContext.resume();
		if(document.getElementById("fsbut")){
			document.getElementById("fsbut").setAttribute('style', 'display: block');
		}
		init();
	}
</script>

<script>
	document.addEventListener('webkitfullscreenchange', fsHandler, false);
    	document.addEventListener('mozfullscreenchange', fsHandler, false);
    	document.addEventListener('fullscreenchange', fsHandler, false);
    	document.addEventListener('MSFullscreenChange', fsHandler, false);
      
    function fsHandler(){
 	     var elem = document.getElementById("main");
         var state = document.fullScreen || document.mozFullScreen || document.webkitIsFullScreen;
         if(state){
         	elem.style.width="100%";
      		elem.style.height="100%";
    	 	elem.children[0].style.width="100%";
      		elem.children[0].style.height="100%";
         }
         else{
         	elem.style.width="";
      		elem.style.height="";
    		elem.children[0].style.width="";
      		elem.children[0].style.height="";
         }
    
    }
    
	function fullscr(elemId) {
      var elem = document.getElementById("main");
      if (elem.requestFullscreen) {
        elem.requestFullscreen();
      } else if (elem.mozRequestFullScreen) {
        elem.mozRequestFullScreen();
      } else if (elem.webkitRequestFullScreen) {
        elem.webkitRequestFullScreen(Element.ALLOW_KEYBOARD_INPUT);
      }
    }
</script>
<style type="text/css"> 
      body {
        margin: 0;
        padding: 0;
        font-family: Helvetica;
      }

/**
  Tutorial : Comments System with Reply Usong jQuery & Ajax
  Author: Amine Kacem
  Author URI: http://www.webcodo.com
*/

/* the comments container  */
.cmt-container{ 
	width: 540px;
	height: auto; min-height: 30px;
	padding: 10px;
	margin: 10px auto;
	background-color: #1c3740;
	border: #d3d6db 1px solid;
	-webkit-border-radius: 12px; -moz-border-radius: 12px; border-radius: 12px;
} 

.cmt-cnt{
	width: 100%; height: auto; min-height: 35px; 
	padding: 5px 0;
	overflow: auto;
}
.cmt-cnt img{
	width: 35px; height: 35px; 
	float: left; 
	margin-right: 10px;
	-webkit-border-radius: 3px; -moz-border-radius: 3px; border-radius: 3px;
	background-color: #ccc;
}
.thecom{
	width: auto; height: auto; min-height: 35px; 
	background-color: #1c3740;
	border: #FFF 1px solid;
	font: 14px 'Segoe UI', 'Proxima Nova', 'Helvetica Neue', Helvetica, Arial, sans-serif;   margin: 0;
}
.thecom h5{
	display: inline;
	float: left;
	font-family: tahoma;
	font-size: 15px;
	color: #3b5998;
	margin: 0 15px 0 5px;
}
.thecom .com-dt{
	display: inline;
	float: left;
	font-size: 12px; 
	line-height: 18px;
	color: #4e5665;
}
.thecom p{
	width: auto;
	margin: 5px 5px 5px 45px;
	color: #ccc;
text-align: left;
}
.new-com-bt{
	width: 100%;
	 padding: 5px;
}
.new-com-bt span{
	display: inline;
	font-size: 13px;
	margin-left: 10px;
	line-height: 30px;
}
.new-com-cnt{ width: 100%; height: auto; min-height: 110px; }
.the-new-com{ /* textarea */
	width: 98%; height: auto; min-height: 70px;
	padding: 5px; margin-bottom: 8px;
	border: #d3d7dc 1px solid;
	-webkit-border-radius: 3px; -moz-border-radius: 3px; border-radius: 3px;
	background-color: #f9f9f9;
	color: #333;
	resize: none;
}
.new-com-cnt input[type="text"]{
	margin: 0;
	height: 20px;
	padding: 5px;
	border: #d3d7dc 1px solid;
	-webkit-border-radius: 3px; -moz-border-radius: 3px; border-radius: 3px;
	background-color: #f9f9f9;
	color: #333;
	margin-bottom:5px;
}
.cmt-container textarea:focus, .new-com-cnt input[type="text"]:focus{
	border-color: rgba(82, 168, 236, 0.8);
  outline: 0;
  outline: thin dotted \9;
  /* IE6-9 */
  -webkit-box-shadow: inset 0 1px 1px rgba(0, 0, 0, 0.075), 0 0 8px rgba(82, 168, 236, 0.4);
     -moz-box-shadow: inset 0 1px 1px rgba(0, 0, 0, 0.075), 0 0 8px rgba(82, 168, 236, 0.4);
          box-shadow: inset 0 1px 1px rgba(0, 0, 0, 0.075), 0 0 8px rgba(82, 168, 236, 0.4);
}
.bt-add-com{
	display: inline;
	//float: left;
	padding: 8px 10px;  margin-right: 10px;
	background-color: #3498db;
	color: #fff; cursor: pointer;
	opacity: 0.6;
	-webkit-border-radius: 3px; -moz-border-radius: 3px; border-radius: 3px;
}
.bt-cancel-com{
	display: inline;
	//float: left;
	padding: 8px 10px; 
	border: #d9d9d9 1px solid;
	background-color: #fff;
	color: #404040;	cursor: pointer;
	-webkit-border-radius: 3px; -moz-border-radius: 3px; border-radius: 3px;
}
.new-com-cnt{ 
	width:100%; height: auto; 
	display: none;
	padding-top: 10px; margin-bottom: 10px;
	border-top: #d9d9d9 1px dotted;
}


/* Css Shadow Effect for the prod-box and prod-box-list div */
 .shadow{
    -webkit-box-shadow: 0px 0px 18px rgba(50, 50, 50, 0.31);
    -moz-box-shadow:    0px 0px 10px rgba(50, 50, 50, 0.31);
    box-shadow:         0px 0px 5px rgba(50, 50, 50, 0.31);
}	
	canvas {
		  image-rendering: optimizeSpeed;             /* Older versions of FF          */
		  image-rendering: -moz-crisp-edges;          /* FF 6.0+                       */
		  image-rendering: -webkit-optimize-contrast; /* Safari                        */
		  image-rendering: -o-crisp-edges;            /* OS X & Windows Opera (12.02+) */
		  image-rendering: pixelated;                 /* Awesome future-browsers       */
		  -ms-interpolation-mode: nearest-neighbor;   /* IE                            */
	}

    </style> 
</head> 
<body  onload="initHack();" bgcolor="#333">
<br>
<center>
<div id="main"></div>
<button id="fsbut" style="display: none" onclick="fullscr('main');">Fullscreen</button>
</center>
<table width=100%>
<tr>
<td>
Author : Shiftcode</td>
<td align=right>
Date : 2022-09-30<br>
</td>
</tr>
</table>
<center>
<a href="javascript:window.open('https://www.facebook.com/sharer/sharer.php?u=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D543', '_blank', 'width=600,height=400');void(0);"><img src="images/FB.png" alt="share on facebook"/></a>
<a href="javascript:window.open('https://twitter.com/intent/tweet?original_referer=http%3A%2F%2Fwww.wab.com%2F&related=alonetrio&text=Another+Nice+html5+screen+from+Shiftcode+using+CODEF.+%28Use+Chrom+e%2Fium+for+perf+and+sound+%3B%29+%29&tw_p=tweetbutton&url=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D543&via=alonetrio', '_blank', 'width=600,height=400');void(0);"><img src="images/TW.png"></a>



<div class="cmt-container" >
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>StrangerHMD</h5><span data-utime="1371248446" class="com-dt">2022-10-07 13:24:49</span>
            <br/>
            <p>
                Cool legendary prod!            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
    

    <div class="new-com-bt">
	<button>Write a Comment...</button>
    </div>
    <div class="new-com-cnt">
        <input type="text" id="name-com" name="name-com" value="" placeholder="Your name" />
        <input type="text" id="mail-com" name="mail-com" value="" placeholder="Your e-mail adress" />
        <textarea class="the-new-com"></textarea>
        <div class="bt-add-com">Post comment</div>
        <div class="bt-cancel-com">Cancel</div>
    </div>
    <div class="clear"></div>
</div><!-- end of comments container "cmt-container" -->



</center>
<script src="/js/jquery.min.js" type="text/javascript"></script>
<script src="/js/core.js" type="text/javascript"></script>
<script type="text/javascript">
   $(function(){ 
        //alert(event.timeStamp);
        $('.new-com-bt').click(function(event){    
            $(this).hide();
            $('.new-com-cnt').show();
            $('#name-com').focus();
        });

        /* when start writing the comment activate the "add" button */
        $('.the-new-com').bind('input propertychange', function() {
           $(".bt-add-com").css({opacity:0.6});
           var checklength = $(this).val().length;
           if(checklength){ $(".bt-add-com").css({opacity:1}); }
        });

        /* on clic  on the cancel button */
        $('.bt-cancel-com').click(function(){
            $('.the-new-com').val('');
            $('.new-com-cnt').fadeOut('fast', function(){
                $('.new-com-bt').fadeIn('fast');
            });
        });

        // on post comment click 
        $('.bt-add-com').click(function(){
            var theCom = $('.the-new-com');
            var theName = $('#name-com');
            var theMail = $('#mail-com');

            if( !theCom.val()){ 
                alert('You need to write a comment!'); 
            }else{ 
                $.ajax({
                    type: "POST",
                    url: "comment/add-comment.php",
                    data: 'act=add-com&id_post='+543+'&name='+theName.val()+'&email='+theMail.val()+'&comment='+theCom.val(),
                    success: function(html){
                        theCom.val('');
                        theMail.val('');
                        theName.val('');
                        $('.new-com-cnt').hide('fast', function(){
                            $('.new-com-bt').show('fast');
                            $('.new-com-bt').before(html);  
                        })
                    }  
                });
            }
        });

    });
</script>

</body>
</html>
