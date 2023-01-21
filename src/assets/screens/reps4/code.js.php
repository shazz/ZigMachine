
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
<script src="//codef.santo.fr/codef/codef_fx.js"></script>


<script>

var font = new image('screens/028/fonts2.png');
var fontMask = new image('screens/028/fontsMask3.png');
var logo = new image('screens/028/logo.png');
var background = new image('screens/028/background.png');
var backgroundMask = new image('screens/028/backgroundMask.png');

var rasterBlue = new image('screens/028/rasterBlue.png');
var rasterGray = new image('screens/028/rasterGray.png');
var rasterYellow = new image('screens/028/rasterYellow.png');
var rasterPink = new image('screens/028/rasterPink.png');
var rasterFonts = new image('screens/028/rasterFont4.png');

var maincanvas;
var scrolltext;
var mergecanvas;
var scrollcanvas;

var rastersCanvas;

var offscreencanvas;
var fx;
var fxparam=[
		{value: 0, amp: 20, inc:0.06, offset: -0.06},
	      ];

var player = new music("YM");

function init()
{
	player.LoadAndRun('screens/028/Pro BMX Simulator A.ym');

	maincanvas=new canvas(640,400,"main");
	offscreencanvas=new canvas(640,326);
	mergecanvas=new canvas(640,326);
	scrollcanvas=new canvas(640, 60);

	rastersCanvas=new canvas(640,360);
	for(var i=0; i<6; i++){
		rasterFonts.draw(rastersCanvas,0,i*60);
	}

	//this.initTile=function(tilew,tileh,tilestart){
	rasterFonts.initTile(640,2);

	logo.draw(offscreencanvas,18,0);

	font.initTile(32,32,32);
	scrolltext = new scrolltext_horizontal();
	scrolltext.scrtxt=" THE UNION PRESENTS : - GARFIELD - CRACKED BY DOM FROM THE REPLICANTS MEMBER OF THE UNION. MEMBERS OF THE REPLICANTS ARE : ELWOOD(NEW MEMBER!!),DOM,<R.AL>,SNAKE,COBRA,KNIGHT 2OO1,GO HAINE,EXCALIBUR,RANK-XEROX,HANNIBAL,GOLDORAK...... HI TO : LOCKBUSTERS,THE BLADE RUNNERS,B.O.S.S,WAS (NOT WAS),MCA,THE PREDATORS     A SPECIAL HI TO ALL MEMBERS OF THE MICRO CLUB LILLOIS!!!!!!!!........BYE BYE.......SEE YOU A NEXT TIME....      ";
	scrolltext.init(scrollcanvas,font,3.5);

	fx=new FX(offscreencanvas,mergecanvas,fxparam);

	go();
}

var logoTop = 16;
var logoBottom = 282;
var logoPos = 16;
var logoPosInc = 1.8;

var rastersTop = 50;
var rastersBottom = 270

var rasterBluePos = rastersTop;
var rasterBluePosInc = 1.5;
var rasterPinkPos = rastersTop+100;
var rasterPinkPosInc = 1.5;
var rasterYellowPos = rastersTop+200;
var rasterYellowPosInc = 1.5;
var rasterGrayPos = 192;
var rasterGrayPosInc = -1.5;

var rasterFontPos = 0;
//var a = 0;

function go()
{
	maincanvas.fill('#000000');
	mergecanvas.clear();
	scrollcanvas.clear();

	fx.sinx(0,0);
	logoPos += logoPosInc;
	if(logoPos  <= logoTop+10) logoPosInc = 1.8;
	if(logoPos  >= logoBottom) logoPosInc = -1.8


	// draw rasters
	rasterBlue.draw(maincanvas, 0, rasterBluePos);
	rasterBluePos += rasterBluePosInc
	if(rasterBluePos < rastersTop || rasterBluePos > rastersBottom)  rasterBluePosInc = -rasterBluePosInc;

	rasterPink.draw(maincanvas, 0, rasterPinkPos);
	rasterPinkPos += rasterPinkPosInc
	if(rasterPinkPos < rastersTop || rasterPinkPos > rastersBottom)  rasterPinkPosInc = -rasterPinkPosInc;

	rasterYellow.draw(maincanvas, 0, rasterYellowPos);
	rasterYellowPos += rasterYellowPosInc
	if(rasterYellowPos < rastersTop || rasterYellowPos > rastersBottom)  rasterYellowPosInc = -rasterYellowPosInc;

	rasterGray.draw(maincanvas, 0, rasterGrayPos);
	rasterGrayPos += rasterGrayPosInc
	if(rasterGrayPos < rastersTop || rasterGrayPos > rastersBottom)  rasterGrayPosInc = -rasterGrayPosInc;

	// draw background
	background.draw(maincanvas, 0, 0);

	// scrolltext
	scrolltext.draw(26);
	scrollcanvas.contex.globalCompositeOperation='source-atop';
	fontMask.draw(scrollcanvas, 0, 0);
	scrollcanvas.draw(maincanvas, 32, 316);
	scrollcanvas.contex.globalCompositeOperation='source-over';

	// draw raster fonts inside logo using source-atop
	mergecanvas.contex.globalCompositeOperation='source-in';

	// draw rasters back scroller
	var dir = 0;
	if(logoPosInc > 0) dir = -1; else dir = 1;

	/* works well with tiles but only on chrome :(
	a+=1.8;
	for(var i=0; i<230/2;i++)
	{
		rasterFonts.drawTile(mergecanvas,((dir*i)+a)%30, 0,60 + (i*2));
	}
	*/

	rastersCanvas.draw(mergecanvas,0,rasterFontPos);
	rasterFontPos -= (dir*3);
	if(rasterFontPos >=60) rasterFontPos=0;
	if(rasterFontPos <=-60) rasterFontPos=0;


	// draw resulting buffer on screen canvas
	mergecanvas.drawPart(maincanvas, 50,logoPos, 0,logoPos-logoTop, 640, 58, 1.0, 0, 1.0, 1.0);
	mergecanvas.contex.globalCompositeOperation='source-over';

	// draw mask
	backgroundMask.draw(maincanvas, 0,294);

	counter++;
	requestAnimFrame( go );
}

var counter = 0;

</script><script>
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
Author : Shazz</td>
<td align=right>
Date : 2011-12-09<br>
</td>
</tr>
</table>
<center>
<a href="javascript:window.open('https://www.facebook.com/sharer/sharer.php?u=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D28', '_blank', 'width=600,height=400');void(0);"><img src="images/FB.png" alt="share on facebook"/></a>
<a href="javascript:window.open('https://twitter.com/intent/tweet?original_referer=http%3A%2F%2Fwww.wab.com%2F&related=alonetrio&text=Another+Nice+html5+screen+from+Shazz+using+CODEF.+%28Use+Chrom+e%2Fium+for+perf+and+sound+%3B%29+%29&tw_p=tweetbutton&url=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D28&via=alonetrio', '_blank', 'width=600,height=400');void(0);"><img src="images/TW.png"></a>



<div class="cmt-container" >
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>Shazz</h5><span data-utime="1371248446" class="com-dt">2011-12-09 00:00:00</span>
            <br/>
            <p>
                A classic from DOM to celebrate the fact the Reps integrated the Union... if I remember well.            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>Dr.Death / Dawn</h5><span data-utime="1371248446" class="com-dt">2011-12-11 00:00:00</span>
            <br/>
            <p>
                Sorry mate this just plays the music for me  :(             </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>ryt</h5><span data-utime="1371248446" class="com-dt">2011-12-12 00:00:00</span>
            <br/>
            <p>
                good tune            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>Shazz</h5><span data-utime="1371248446" class="com-dt">2011-12-13 00:00:00</span>
            <br/>
            <p>
                Dr. Death, which browser/version are you using ?            </p>
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
                    data: 'act=add-com&id_post='+28+'&name='+theName.val()+'&email='+theMail.val()+'&comment='+theCom.val(),
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
