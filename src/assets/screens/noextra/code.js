
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
<script src="//codef.santo.fr/codef/codef_fx.js"></script> 
<script src="//codef.santo.fr/codef/codef_scrolltext.js"></script> 
<script src="//codef.santo.fr/codef/codef_music.js"></script> 

<script> 

var basepath = "screens/198/" ;

var player = new music("YM");
player.LoadAndRun(basepath + 'mega4.ym');

var backraster=new image(basepath + 'backraster.png');
var grad_bar=new image(basepath + 'grad_bar.png');
var toplogo=new image(basepath + 'toplogo.png');
var bottomlogo=new image(basepath + 'bottomlogo.png');
var dhs=new image(basepath + 'dhs.png');

var font=new image(basepath + 'fontw.png');

var mycanvas;
var mycanvas2;
var offscreencanvas1;
var offscreencanvas2;
var scrollcanvas;
var distcanvas1;
var distcanvas2;

var scrolltext;

var time=0;
var fade=0;
var y=120;
var yinc=2;
var flag=0;
var fx=0;
var yy=0;
var yyinc=-3;

var myfx1;
var myfxparam1=[
		{value: 0, amp: 150, inc:0.04, offset: -0.05},
		{value: 0, amp: -100, inc:0.01, offset:  0.08}
	      ];
var scrollfx;
var scrollfxparam=[
		{value: 0, amp: 100, inc:0.0005, offset: 0.02}
	      ];

var text="    1..........2..........3..........4..........5..........6..........7..........8.........9.........10..........         ]          ";
text+=" HERE WE GO ! ! !         WELCOME ON THE GREAT COMPILATION OF D.H.S.  :  THE ST DEMOSCREEN COMPETITION. ";
text+="            THANK YOU MR EVIL FOR PUTTING FORWARD THIS EVENT AT THE END OF THE YEAR 2005 AND GOOD LUCK ";
text+="TO THE COMPETITORS. THE PRIZES ARE VERY INTERESTING!!!         I WANT TO THANK THE CREW NOEXTRA TO PERMIT ";
text+="ME TO CODE WITH THEM.  THANK YOU TO ATOMUS AND BIG DISQUE TO MISTER A WHO LIVE IN ITALY.         ";
text+="....THAT'S ENOUGH OF THAT..... THIS IS MELLOWMAN HERE, BRINGING YOU HIS REMAKE OF THIS 2005 MEGADEMO SCREEN ";
text+="BY NOEXTRA TEAM! PART OF THE DHS MEGADEMO 2005..... HOPE YOU LIKE IT! GREETZ GOTO: NONAMENO, TOTORMAN, SOLO, ";
text+="FLUTTERSHY, AYOROS-IMPACT, JOHN MINDFUL, SHAZZ-TRSI, NEW CORE, AND ALL THE OTHER CODEF DUDES OUT THERE!!........        ";
 
function init(){
	mycanvas=new canvas(640,480,"main");
	dhs.setmidhandle();
	
	prego1();
}

function prego1(){
	mycanvas.fill('#000000'); 
	dhs.draw(mycanvas,320,y,fade,0,1,1);
	fade+=0.01;
	if(fade>2){
		fade=1;
		requestAnimFrame( prego2 );
	}
	else
	requestAnimFrame( prego1 );
}

function prego2(){
	mycanvas.fill('#000000'); 
	dhs.draw(mycanvas,320,y);
	y+=yinc;
	if(y>=320) yinc=-2;
	if(y<=120) yinc=2;
	if(y==220) flag+=1; 
	if(flag>=6) {
		if (y==300) yinc=0; y=220; requestAnimFrame( prego3 );
		}
	else
	requestAnimFrame( prego2 );
}

function prego3(){
	mycanvas.fill('#000000');
	dhs.draw(mycanvas,320,220,fade,0,1,1);
	fade-=0.01;
	if(fade<0){
		fade=0;
		requestAnimFrame( init2 );
	}
	else
	requestAnimFrame( prego3 );
}

function init2(){
	mycanvas2=new canvas(640,480);
	offscreencanvas1=new canvas(640,240);
	scrollcanvas=new canvas(640,240);
	offscreencanvas2=new canvas(640,480);
	distcanvas1=new canvas(1280,240);
	distcanvas2=new canvas(1280,240);

	backraster.draw(distcanvas1,0,0);
	myfx1=new FX(distcanvas1,distcanvas2,myfxparam1);
	
	font.initTile(64,34,32);
	scrolltext = new scrolltext_horizontal();
	scrolltext.scrtxt=text;
	scrolltext.init(offscreencanvas1,font,9);
	scrollfx=new FX(offscreencanvas1,scrollcanvas,scrollfxparam);

	go();
}	

function go(){
	mycanvas.fill('#000000');
	mycanvas2.clear();
	distcanvas2.clear();
	offscreencanvas1.clear();
	offscreencanvas2.clear();
	scrollcanvas.clear();	

	myfx1.sinx(0,0);
	distcanvas2.draw(offscreencanvas2,-250,100,1,0,0.9,1);       
	grad_bar.draw(offscreencanvas2,0,100);
	grad_bar.draw(offscreencanvas2,0,338);

	scrolltext.draw(0);
	scrollfx.siny(0,100);

	toplogo.draw(offscreencanvas2,110,0);
	bottomlogo.draw(offscreencanvas2,125,342);

	offscreencanvas2.draw(mycanvas2,0,0);
	scrollcanvas.draw(mycanvas2,0,100);

	switch (parseInt(scrolltext.scrtxt.charCodeAt(scrolltext.scroffset))){
		case 93:
			// key=]
			fx = 1;
			break;
		}

	if (fx==0) mycanvas2.draw(mycanvas,0,0);
	if (fx==1) {
		mycanvas2.draw(mycanvas,0,yy);
		yy+=yyinc;
		if (yy>=80) yyinc=-3;
		if (yy<=-80) yyinc=3;
		}

	requestAnimFrame( go );
}
 
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
Author : MellowMan</td>
<td align=right>
Date : 2013-05-24<br>
</td>
</tr>
</table>
<center>
<a href="javascript:window.open('https://www.facebook.com/sharer/sharer.php?u=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D198', '_blank', 'width=600,height=400');void(0);"><img src="images/FB.png" alt="share on facebook"/></a>
<a href="javascript:window.open('https://twitter.com/intent/tweet?original_referer=http%3A%2F%2Fwww.wab.com%2F&related=alonetrio&text=Another+Nice+html5+screen+from+MellowMan+using+CODEF.+%28Use+Chrom+e%2Fium+for+perf+and+sound+%3B%29+%29&tw_p=tweetbutton&url=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D198&via=alonetrio', '_blank', 'width=600,height=400');void(0);"><img src="images/TW.png"></a>



<div class="cmt-container" >
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>Zorro2^NoExtra</h5><span data-utime="1371248446" class="com-dt">2013-05-26 00:00:00</span>
            <br/>
            <p>
                Really nice Plasma mister Mellow Man ;)            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>Mellow Man</h5><span data-utime="1371248446" class="com-dt">2013-05-30 00:00:00</span>
            <br/>
            <p>
                Great original screen, and was a pleasure to remake, very happy you like it!!            </p>
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
                    data: 'act=add-com&id_post='+198+'&name='+theName.val()+'&email='+theMail.val()+'&comment='+theCom.val(),
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
