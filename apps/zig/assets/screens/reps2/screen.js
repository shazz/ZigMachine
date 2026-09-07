
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
<script src="//codef.santo.fr/codef/codef_music.js"></script> 
<script src="//codef.santo.fr/codef/codef_scrolltext.js"></script> 
<script src="//codef.santo.fr//codef/codef_gradient.js"></script> 

<script> 
var player = new music("YM");
player.LoadAndRun('screens/030/Forgotten Worlds.ym');
document.onkeydown = KeyCheck;

function KeyCheck(ev){
	if (!ev) var ev=window.event;
	var KeyID = ev.keyCode;

	//alert(KeyID);

	switch(KeyID){
		case 97:
			if(++framespeed > 1 ) framespeed=1;
			ev.preventDefault();
        		return false;
			break;
		case 98:
			if(--framespeed < -1 ) framespeed=-1;
			ev.preventDefault();
        		return false;
			break;
		case 100:
			if(++mt03speed > 16 ) mt03speed=16;
			ev.preventDefault();
        		return false;
			break;
		case 101:
			if(--mt03speed < -16 ) mt03speed=-16;
			ev.preventDefault();
        		return false;
			break;
		case 103:
			if(++mt02speed > 16 ) mt02speed=16;
			ev.preventDefault();
        		return false;
			break;
		case 104:
			if(--mt02speed < -16 ) mt02speed=-16;
			ev.preventDefault();
        		return false;
			break;
		case 57:
			if(++mt01speed > 1 ) mt01speed=1;
			ev.preventDefault();
        		return false;
			break;
		case 48:
			if(--mt01speed < -1 ) mt01speed=-1;
			ev.preventDefault();
        		return false;
			break;

	}
}
 
var mycanvas;
var mt01big;
var mt02big;
var mt02big;
var mycanvasscr;
var myscroll1cvs;
var myscroll1cvsrv;

var chess = new Array();
for(var i=0; i<=13; i++){
	chess[i]=new image('screens/030/bg'+eval(i+1)+'.png');
}

var mt01 = new image('screens/030/mt01.png');
var mt02 = new image('screens/030/mt02.png');
var mt03 = new image('screens/030/mt03.png');
var sky = new image('screens/030/sky.png');
var myfont = new image('screens/030/font.png');

var mylogo = new image('screens/030/logo.png');

var mycred1 = new image('screens/030/cred1.png');
var mycred2 = new image('screens/030/cred2.png');


var myscrolltext;

var mygrad1;
var mygradcolor1=
	[
	{color: 'rgb(0,0,0)' ,  offset:0},
	{color: 'rgb(255,0,0)' ,  offset:0.5},
	{color: 'rgb(0,0,0)' ,  offset:1}

	];

var mygrad2;
var mygradcolor2=
	[
	{color: 'rgb(30,0,0)' ,  offset:0},
	{color: 'rgb(100,0,0)' ,  offset:0.5},
	{color: 'rgb(30,0,0)' ,  offset:1}

	];


 
function init(){
	mycanvas=new canvas(640,420,"main");
	mt01big=new canvas(640*3,118);
	mt01.draw(mt01big,0,0);mt01.draw(mt01big,640,0);mt01.draw(mt01big,1280,0);
	mt02big=new canvas(640*3,146);
	mt02.draw(mt02big,0,0);mt02.draw(mt02big,640,0);mt02.draw(mt02big,1280,0);
	mt03big=new canvas(640*3,34);
	mt03.draw(mt03big,0,0);mt03.draw(mt03big,640,0);mt03.draw(mt03big,1280,0);
	
	mycanvasscr=new canvas(32,38*80);
	mycanvasscr.initTile(32,1,0);

	myscroll1cvs = new canvas(640,38*3);
	myscroll1cvsdeg = new canvas(640,38*3);
	myscroll1cvsrv = new canvas(640,38*3);
	myscroll1cvsrvdeg = new canvas(640,38*3);

	mygrad1=new grad(myscroll1cvsdeg,mygradcolor1);
	mygrad1.drawH();

	mygrad2=new grad(myscroll1cvsrvdeg,mygradcolor2);
	mygrad2.drawH();

	myfont.initTile(32,38,32);
	myscrolltext = new scrolltext_vertical();
	myscrolltext.scrtxt="HELLO !!!   HERE IT IS THE NEW RATBOY'S INTRO FOR THE REPLICANTS (HEY !  IT'S ME !). WHAT DO YOU THINK OF THIS SCROLL ?...  NOT SO BAD !     OH !, OH !, OH !...  TRY THE KEYS 1,2,4,5,7,8,(,),-,PLUS TO CHANGE THE SPEED OF EACH SCROLL...       AND TO MODIFY THE WAVE FORM        THE REPLICANTS ARE COMPOSED BY: RATBOY - SNAKE - < RAL > - FURY DOM - COBRA - ELWOOD - EXCALIBUR       HERE IT IS THE GREETINGS TO MCA (ESPECIALLY HARRIE !), THE UNION, WAS (NOT WAS), TCB, BANZAI, JABBERWOCKY, D.C.S (ESPECIALLY R-ZAUGH).  BIG HI TO 'CET ENFOIRE DE JEAN MARC'.    MY FUCKING ARE SEND TO ALL THE LOOSERS AND LAMERS THAT SAY  I DON'T KNOW HOW TO PROGRAMM ! MAY THE EVIL SUCKS YOUR MOTHER.      SO, IT'S TIME TO SAY YOU GOODBYYYYYYYYE....  "
	myscrolltext.init(mycanvasscr,myfont,3);

	credit1in();
}

var tmp=0;
function credit1in(){
	mycanvas.fill('#000000');
	mycred1.draw(mycanvas,0,0,tmp);
	tmp+=0.005;

	if (tmp>=1){
		credit1out();
	}
	else
		requestAnimFrame( credit1in );
}

function credit1out(){
	mycanvas.fill('#000000');
	mycred1.draw(mycanvas,0,0,tmp);
	tmp-=0.005;

	if (tmp<=0){
		tmp=0;
		credit2in();
	}
	else
		requestAnimFrame( credit1out );
}

function credit2in(){
	mycanvas.fill('#000000');
	mycred2.draw(mycanvas,0,0,tmp);
	tmp+=0.005;

	if (tmp>=1){
		credit2out();
	}
	else
		requestAnimFrame( credit2in );
}

function credit2out(){
	mycanvas.fill('#000000');
	mycred2.draw(mycanvas,0,0,tmp);
	tmp-=0.005;

	if (tmp<=0){
		tmp=0;
		go();
	}
	else
		requestAnimFrame( credit2out );
}


var frame=0;
var framespeed=1;
var mt01posx=-640;
var mt01speed=1;
var mt02posx=-640;
var mt02speed=2;
var mt03posx=-640;
var mt03speed=3;
function go(){
	mycanvas.fill('#000000');
	mycanvasscr.clear();
	myscroll1cvs.clear();
	myscroll1cvsrv.clear();

	sky.draw(mycanvas,0,0);
	mt01big.draw(mycanvas,mt01posx,10);
	mt02big.draw(mycanvas,mt02posx,80);
	mt03big.draw(mycanvas,mt03posx,140);
	chess[frame].draw(mycanvas,0,174);

	frame+=framespeed;
	if(framespeed>0){
		if(frame > 13) frame=0;
	}
	else{
		if(frame < 0) frame=13;
	}
	mt01posx-=mt01speed;
	if(mt01posx <= -1280) mt01posx=-640;
	if(mt01posx >= 0) mt01posx=-640;
	mt02posx-=mt02speed;
	if(mt02posx <= -1280) mt02posx=-640;
	if(mt02posx >= 0) mt02posx=-640;
	mt03posx-=mt03speed;
	if(mt03posx <= -1280) mt03posx=-640;
	if(mt03posx >= 0) mt03posx=-640;

	myscrolltext.draw(0);
	var decal=0;
	for(var y=113;y>=0;y--){
		mycanvasscr.drawTile(myscroll1cvs,3039-113*1+y,608-decal-64*0,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*3+y,608-decal-64*1,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*5+y,608-decal-64*2,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*7+y,608-decal-64*3,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*9+y,608-decal-64*4,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*11+y,608-decal-64*5,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*13+y,608-decal-64*6,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*15+y,608-decal-64*7,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*17+y,608-decal-64*8,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*19+y,608-decal-64*9,y);
		mycanvasscr.drawTile(myscroll1cvs,3039-113*21+y,608-decal-64*10,y);


		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*1-y,608+decal-64*1,y);
		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*3-y,608+decal-64*2,y);
		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*5-y,608+decal-64*3,y);
		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*7-y,608+decal-64*4,y);
		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*9-y,608+decal-64*5,y);
		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*11-y,608+decal-64*6,y);
		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*13-y,608+decal-64*7,y);
		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*15-y,608+decal-64*8,y);
		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*17-y,608+decal-64*9,y);
		mycanvasscr.drawTile(myscroll1cvsrv,3039-113*19-y,608+decal-64*10,y);


		decal+=0.2;
	}

	myscroll1cvs.contex.globalCompositeOperation='source-in';
	myscroll1cvsdeg.draw(myscroll1cvs,0,0);
	myscroll1cvs.contex.globalCompositeOperation='source-over';

	myscroll1cvsrv.contex.globalCompositeOperation='source-in';
	myscroll1cvsrvdeg.draw(myscroll1cvsrv,0,0);
	myscroll1cvsrv.contex.globalCompositeOperation='source-over';

	myscroll1cvsrv.draw(mycanvas,0,300);
	mylogo.draw(mycanvas,22,330);
	myscroll1cvs.draw(mycanvas,0,300);

	requestAnimFrame( go );
}
 
</script> <script>
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
Author : NoNameNo</td>
<td align=right>
Date : 2011-12-14<br>
</td>
</tr>
</table>
<center>
<a href="javascript:window.open('https://www.facebook.com/sharer/sharer.php?u=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D30', '_blank', 'width=600,height=400');void(0);"><img src="images/FB.png" alt="share on facebook"/></a>
<a href="javascript:window.open('https://twitter.com/intent/tweet?original_referer=http%3A%2F%2Fwww.wab.com%2F&related=alonetrio&text=Another+Nice+html5+screen+from+NoNameNo+using+CODEF.+%28Use+Chrom+e%2Fium+for+perf+and+sound+%3B%29+%29&tw_p=tweetbutton&url=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D30&via=alonetrio', '_blank', 'width=600,height=400');void(0);"><img src="images/TW.png"></a>



<div class="cmt-container" >
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>Peace</h5><span data-utime="1371248446" class="com-dt">2011-12-14 00:00:00</span>
            <br/>
            <p>
                I don't know this cracktro, but the scroller looks really cool!            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>mantru</h5><span data-utime="1371248446" class="com-dt">2012-01-27 00:00:00</span>
            <br/>
            <p>
                yees            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>Calx</h5><span data-utime="1371248446" class="com-dt">2012-08-29 00:00:00</span>
            <br/>
            <p>
                This is just perfect, great work.            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>JustZisGuy</h5><span data-utime="1371248446" class="com-dt">2012-08-30 00:00:00</span>
            <br/>
            <p>
                Love the song. Anyone know if it's original or a cover?            </p>
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
                    data: 'act=add-com&id_post='+30+'&name='+theName.val()+'&email='+theMail.val()+'&comment='+theCom.val(),
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
