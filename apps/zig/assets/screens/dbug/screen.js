
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

<script> 
var basepath = "screens/556/";
var ctrLoaded = 0, elemsToLoad = 4, mainCanvas, ctx, scrolltext, font, littleBigFont, bigFont, logo, soundchip, started=false, ctrSpring=-1;
var lettersCan, letters=[], letterWait=0, currentPattern=0, currentText=0, ctrLetter=0, letterDirection=1, letterSizes = [0,8,10,14,18,22,28], letterSpaces = [0,12,11,9,7,5,2];
// Music sync purposes :
const fallAt = 12800, startBeatAt = 13600, stopBeatAt = 89600, restartAt = 102400, beatInterval = 1608;
var nextBeat = startBeatAt, musicStep=0, guiTimeline=0, lastHit, ctrBounce;

font = new image(basepath + "yellow_font_32x28.png");
littleBigFont = new image(basepath + "big_font_32x24.png");
logo = new image(basepath + "logo.png");
font.img.onload = littleBigFont.img.onload = logo.img.onload = countLoaded;

// SNDH Player
loadAllScripts(basepath, [
  'data.js',
  'scriptprocessor_player.js',
  'backend_sc68.js',
  'sndh-player-v2.js'
]).then(countLoaded)
.catch((url) => console.log('Failed to load script ' + url));

// ============== INIT ===================
function init(){
  mainCanvas = new canvas(768,540,"main");
  ctx = mainCanvas.contex;
  lettersCan = new canvas(20*32, 12*28);
  soundchip = new SndhPlayer(basepath + 'Crystallized.sndh', {
    autostart:false,
    onTrackReadyToPlay:countLoaded,
    onTrackEnd: () => soundchip.init()
  });
  document.getElementById('main').style.backgroundColor = '#000';
  countLoaded();
}

function countLoaded(){
  if(++ctrLoaded > elemsToLoad && !started){
    started = true;
    afterLoad();
  }
}

// =============== AFTER LOAD ============
function afterLoad(){
  var i;
  font.initTile(32,28,32);
  // Builds the big font from bitmap font (32x24 pixels per letter)
  // To prevent canvas size limits (often 32768), we craft a 16x-zoomed image, sliced into 8 lines
  var tmpCanvas = new canvas(4096,384*8);
  var tmpCtx = tmpCanvas.contex;
  tmpCtx.imageSmoothingEnabled = false;
  for(i=0; i<8; i++){
    tmpCtx.drawImage(littleBigFont.img, i*256,0,256,24, 0,i*384,4096,384);
  }
  // Mask for rasters into letters
  var tmpMaskMatrix = tmpCtx.createImageData(4096,384*8);
  var tmpFontMatrix = tmpCtx.getImageData(0,0,4096,684*8);
  for(i=0; i<tmpFontMatrix.data.length; i+=4){
    if(tmpFontMatrix.data[i+2] == 0xAA){  // Blue channel to 0xAA => to be raster-colorized
      tmpMaskMatrix.data[i] = tmpMaskMatrix.data[i+1] = tmpMaskMatrix.data[i+2] = tmpMaskMatrix.data[i+3] = 255;
    } else {
      tmpMaskMatrix.data[i] = tmpMaskMatrix.data[i+1] = tmpMaskMatrix.data[i+2] = tmpMaskMatrix.data[i+3] = 0;
    }
  }
  // Crafts the raster
  var tmpRaster = new canvas(1,384*8);
  '002,002,002,002,102,203,303,403,503,603,703,713,723,732,742,751,761,770,771,772,773,774,775,776,777'.split(',')
  .forEach((c,i,all) => {
    tmpRaster.contex.fillStyle = toRgb(c);
    tmpRaster.contex.fillRect(0,i*14,1,14);
    if(i<all.length-1){
      tmpRaster.contex.fillStyle = toRgb(all[i+1]);
      tmpRaster.contex.fillRect(0,i*14+10,1,2);
    }
  })
  // Repeat raster 8 times
  for(i=0; i<8; i++){
    tmpRaster.contex.drawImage(tmpRaster.canvas, 0,0,1,384, 0,i*384,1,384);
  }
  // Putting all together (mask + raster + pink font border)
  var tmpBigFont = new canvas(4096,384*8);
  var bigCtx = tmpBigFont.contex;
  bigCtx.putImageData(tmpMaskMatrix,0,0);
  bigCtx.globalCompositeOperation = 'source-atop';
  bigCtx.drawImage(tmpRaster.canvas, 0,0,1,384*8, 0,2,4096,384*8);
  bigCtx.globalCompositeOperation = 'destination-over';
  tmpCanvas.draw(tmpBigFont,0,0);
  
  bigFont = new image(tmpBigFont.canvas.toDataURL('image/png'));
  bigFont.img.onload = ()=> {
    bigFont.initTile(512,384,32);
    scrolltext = new scrolltext_horizontal();
    scrolltext.scrtxt = " JUST WHEN YOU THOUGHT WE WERE OUT...WE ARE STILL HERE! THIS MEGA INTRO WAS DONE BY !CUBE OF AGGRESSION, AND IT IS PROBABLY THE BIGGEST REASON YOU ARE SEEING THIS RELEASE AT ALL :P        GREETZ TO ALL THAT DESERVE IT...         LET'S WRAP.............      ";
    scrolltext.init(mainCanvas, bigFont, 16);
    letsgo();
  }
}

function letsgo(){
  soundchip.play();
  setInterval(sndhMonitor, 60);
  go();
}

function go(thisTime){
  mainCanvas.fill('#000');
  guiTimeline = thisTime;
  
  bouncingScroller();
  logoSpring();
  showLetters();
  
  requestAnimFrame(go);
}

// ====================== ROUTINES ===================
// This function asks the player its position (in milliseconds from start time)
// and sync animation
function sndhMonitor(){
  var t = soundchip.getPlaybackPosition();
  if(t > 10000000)
    return; // Inexploitable position, when backend not ready to answer
  switch(musicStep){
    case 0 : // intro
      if(t > fallAt){
        musicStep=1;
        nextBeat = startBeatAt;
        ctrBounce = 0;
        ctrSpring = 0;  // animate the logo
      }
      break;
    case 1 : // falling
    case 2 : // bouncing
      if(t > nextBeat){
        nextBeat += beatInterval;
        lastHit = guiTimeline;
        ctrSpring = 0;  // animate the logo
        musicStep=2;
      }
      if(t > stopBeatAt){
        musicStep=3;
      }
      break;
    case 5 : // end bouncing
      if(t>restartAt){
        musicStep=0;
        soundchip.options.autostart=true;
        soundchip.init();
      }
      break;
  }
}  

function showLetters(){
  if(--letterWait <= 0){
    if(ctrLetter < 240){
      // Which letter to pickup?
      var currentPos = patterns[currentPattern][ctrLetter]
      letters.push({
        l: texts[currentText].charAt(currentPos),
        x: (currentPos % 20) * 32,
        y: Math.floor(currentPos / 20) * 28,
        t: letterDirection==1 ? 0 : 5
      });
    } else {
      // Wait until all letters are shown / hidden
      if(letters.length == 0){
        if(letterDirection==1){
          // end of appearing : will wait a while
          letterWait = 100;
        } else {
          // end of disappearing : change the text
          if(++currentText >= texts.length){
            currentText = 0;
          }
        }
        // in all cases, change the apparition pattern
        if(++currentPattern >= patterns.length){
          currentPattern = 0;
        }
        ctrLetter = -1;
        letterDirection *= -1;
      }
    }
    ctrLetter++;
    
    letters = letters.filter(l=>{
      lettersCan.contex.clearRect(l.x, l.y, 32,28);
      var space = letterSpaces[l.t];
      var size = letterSizes[l.t];
      font.print(lettersCan, l.l, l.x+space, l.y+space, 1,0,size/32,size/28);
      l.t += letterDirection;
      return (l.t>=0 && l.t<=6);
    });
  }
  lettersCan.draw(mainCanvas, 66, 118);
}

function logoSpring(){
  var y = 16;
  if(ctrSpring >= 0){
    y = ysine[ctrSpring++];
    if(ctrSpring >= ysine.length){
      ctrSpring = -1;
    }
  }
  logo.draw(mainCanvas,132,y);
}

function bouncingScroller(){
  var y=74, curveIdx;
  switch(musicStep){
    case 1: // Falling
      y = bounceStart[ctrBounce++];
      break;
    case 2: // Bouncing
      curveIdx = (guiTimeline - lastHit);
      curveIdx = ~~(curveIdx * (bounce.length+5) / beatInterval);
      y = bounce[curveIdx];
      // Animate logo even if beat detection did not worked
      if(y >= 142)
        ctrSpring = 0;
      break;
    case 3: // Waiting for scroller to be at the top of the screen
      curveIdx = (guiTimeline - lastHit) % beatInterval;
      curveIdx = ~~(curveIdx*(bounce.length+5)/beatInterval);
      y = bounce[curveIdx];
      if(y == 0){
        musicStep = 4;
        ctrBounce = 0;
      }
      // Last bounce if any
      if(y >= 142)
        ctrSpring = 0;
      break;
    case 4: // Moving up to return to the default no bouncing position
      y = bounceStop[ctrBounce];
      if(++ctrBounce >= bounceStop.length){
        ctrBounce = 0;
        musicStep = 5;
      }
      break;
  }
  // If beat is a bit late, stick the scroller at the bottom until beat is triggered
  if(y === undefined)
    y=148;
  scrolltext.draw(y);
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

function loadAllScripts(base, scripts){
  if(scripts.length>0)
    return loadScript(base + scripts[0]).then(()=>{loadAllScripts(base, scripts.slice(1))})
}

function toRgb(v) {
  var result="#";
  v.split('').map(k=>parseInt(k)*2).forEach(x=>{result += x.toString(16) + x.toString(16)});
  return result;
}  

function hexaToCurve(curveData){
  result = [];
  for(var i=0; i<curveData.length; i+=2){
    result.push(parseInt(curveData.substr(i,2),16));
  }
  return result;
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
Date : 2022-12-31<br>
</td>
</tr>
</table>
<center>
<a href="javascript:window.open('https://www.facebook.com/sharer/sharer.php?u=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D556', '_blank', 'width=600,height=400');void(0);"><img src="images/FB.png" alt="share on facebook"/></a>
<a href="javascript:window.open('https://twitter.com/intent/tweet?original_referer=http%3A%2F%2Fwww.wab.com%2F&related=alonetrio&text=Another+Nice+html5+screen+from+Shiftcode+using+CODEF.+%28Use+Chrom+e%2Fium+for+perf+and+sound+%3B%29+%29&tw_p=tweetbutton&url=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D556&via=alonetrio', '_blank', 'width=600,height=400');void(0);"><img src="images/TW.png"></a>



<div class="cmt-container" >
    

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
                    data: 'act=add-com&id_post='+556+'&name='+theName.val()+'&email='+theMail.val()+'&comment='+theCom.val(),
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
