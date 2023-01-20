
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
<script src="//codef.santo.fr/codef/codef_3d.js"></script> 
<script src="//codef.santo.fr/codef/codef_decrunch.js"></script> 
<script src="//codef.santo.fr/codef/codef_music.js"></script> 
<script> 
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
Author : NoNameNo</td>
<td align=right>
Date : 2013-01-21<br>
</td>
</tr>
</table>
<center>
<a href="javascript:window.open('https://www.facebook.com/sharer/sharer.php?u=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D124', '_blank', 'width=600,height=400');void(0);"><img src="images/FB.png" alt="share on facebook"/></a>
<a href="javascript:window.open('https://twitter.com/intent/tweet?original_referer=http%3A%2F%2Fwww.wab.com%2F&related=alonetrio&text=Another+Nice+html5+screen+from+NoNameNo+using+CODEF.+%28Use+Chrom+e%2Fium+for+perf+and+sound+%3B%29+%29&tw_p=tweetbutton&url=http%3A%2F%2Fwww.wab.com%2F%3Fscreen%3D124&via=alonetrio', '_blank', 'width=600,height=400');void(0);"><img src="images/TW.png"></a>



<div class="cmt-container" >
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>Jace</h5><span data-utime="1371248446" class="com-dt">2013-01-22 00:00:00</span>
            <br/>
            <p>
                Replicants, Replicants!!!! Cracking is good for U!            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>Shazz/TRSi</h5><span data-utime="1371248446" class="com-dt">2013-01-22 00:00:00</span>
            <br/>
            <p>
                Roooooh you could have ripped the font ! Lazy you are ! I love it anyway.            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>NoNameNo</h5><span data-utime="1371248446" class="com-dt">2013-01-22 00:00:00</span>
            <br/>
            <p>
                @Shazz : Sorry about the font ;) will fixe it tonight ;)            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>NoNameNo</h5><span data-utime="1371248446" class="com-dt">2013-01-22 00:00:00</span>
            <br/>
            <p>
                @Shazz : Done ;)            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>eDDy</h5><span data-utime="1371248446" class="com-dt">2013-02-08 00:00:00</span>
            <br/>
            <p>
                Arf, not the text version where my old crew was mentionned ;)            </p>
        </div>
    </div><!-- end "cmt-cnt" -->
        <div class="cmt-cnt">
        <div class="thecom">
            <h5>6napz</h5><span data-utime="1371248446" class="com-dt">2013-04-16 00:00:00</span>
            <br/>
            <p>
                always loves this cracltro, nice remake!            </p>
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
                    data: 'act=add-com&id_post='+124+'&name='+theName.val()+'&email='+theMail.val()+'&comment='+theCom.val(),
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
