/*
 * +========================================================+
 * | A CODEF/HTML5 remake of the -new- Sowatt sprite record |
 * | (312 Sprites Blast) by Leonard/Oxygene                 |
 * |   http://demozoo.org/productions/67807/                |
 * +--------------------------------------------------------+
 * | Copyleft 2015 by Dyno <dyno@aldabase.com>              |
 * +========================================================+
 */

var
	basepath = 'screens/339/',
	// Main screen size
	screen_width = 384,
	screen_height = 270,
	zoom = 2,
	// Canvas
	main_canvas,
	// Images
	splash1 = new image(basepath + 'splash1.png'),
	splash2 = new image(basepath + 'splash2.png'),
	bee = new image(basepath + 'bee.png'),
	back = new image(basepath + 'back.png'),
	ball = new image(basepath + 'ball.png'),
	// Splash 2
	bee_x = 0,
	bee_dir = 2,
	progress_1 = 0,
	progress_2 = 0,
	// Scrolltext
	font = new image(basepath + 'font.png'),
	text =
		'                                                                  ' +
		'                           ' +
		'HI EVERYBODY ! ULTRA OPTIMISATION RULES, EVEN FOR STUPID RECORD ! ' +
		'I NEVER THOUGH I COULD DISPLAY 312 SPRITES ONE YEAR AGO !  I TOTAL' +
		'LY REWRITE MY PC DATABUILDER TO IMPLEMENT NEW STUFF. THEN, I CHANG' +
		'E THE CLEARING DATA FORMAT TO GET SOME MEMORY LEFT AND THAT IS !TH' +
		'AT DISK SHOULD (I HOPE) RUN ON 520-STF,MEGASTE,TT,FALCON AND EVEN ' +
		'CT60. GREETINGS ARE SENT TO PHANTOM, GUNSTICK AND SOTE. YOU ALL AR' +
		'E COOL OPTIMIZERS !  LEONARD/OXYGENE, 17.03.2005',
	letter = [
		[' ',  0,  0, 3],
		['!',  6,  0, 2],
		['(', 48,  0, 3],
		[')', 54,  0, 3],
		[',', 12,  6, 3],
		['-', 18,  6, 3],
		['.', 24,  6, 2],
		['/', 30,  6, 5],
		['0', 36,  6, 5],
		['1', 42,  6, 3],
		['2', 48,  6, 5],
		['3', 54,  6, 5],
		['4',  0, 12, 5],
		['5',  6, 12, 5],
		['6', 12, 12, 5],
		['7', 18, 12, 5],
		['8', 24, 12, 5],
		['9', 30, 12, 5],
		['A', 18, 18, 5],
		['B', 24, 18, 5],
		['C', 30, 18, 5],
		['D', 36, 18, 5],
		['E', 42, 18, 5],
		['F', 48, 18, 5],
		['G', 54, 18, 5],
		['H',  0, 24, 5],
		['I',  6, 24, 2],
		['J', 12, 24, 5],
		['K', 18, 24, 5],
		['L', 24, 24, 5],
		['M', 30, 24, 5],
		['N', 36, 24, 5],
		['O', 42, 24, 5],
		['P', 48, 24, 5],
		['Q', 54, 24, 5],
		['R',  0, 30, 5],
		['S',  6, 30, 5],
		['T', 12, 30, 4],
		['U', 18, 30, 5],
		['V', 24, 30, 5],
		['W', 30, 30, 5],
		['X', 36, 30, 5],
		['Y', 42, 30, 5],
		['Z', 48, 30, 5]
	],
	// Sprites
	nb_sprites = 312,
	pxa1 = 0,
	pxa2 = 0,
	pya1 = 0,
	pya2 = 0,
	lutSin = [],
	lutCos = [],
	lutLen = 360 * 2,
	// Player
	player,
	// Counters
	iteration = 0;

function draw_sprites() {
	var i, x, y, pxb1 = pxa1, pxb2 = pxa2, pyb1 = pya1, pyb2 = pya2;
	for (i = 0 ; i < nb_sprites ; i++) {
		x = 184 + ((76 * lutCos[mod(pxb1, lutLen)] + 76 * lutSin[mod(pxb2, lutLen)]) >> 15);
		y = 123 + ((44 * lutCos[mod(pyb1, lutLen)] + 44 * lutSin[mod(pyb2, lutLen)]) >> 15);
		ball.draw(main_canvas, x * zoom, y * zoom, 1, 0, zoom, zoom);
		// Inc loop angles
		pxb1 += 7 * 2;
		pxb2 -= 4 * 2;
		pyb1 += 6 * 2;
		pyb2 -= 3 * 2;
	}
	// Inc global angles
	pxa1 += 3 * 2;
	pxa2 += 2 * 2;
	pya1 -= 1 * 2;
	pya2 += 2 * 2;
}

function init() {
	trigo_build();
	// Main canvas
	main_canvas = new canvas(screen_width * zoom, screen_height * zoom, 'main');
	main_canvas.contex.imageSmoothingEnabled = false;
	main_canvas.contex.mozImageSmoothingEnabled = false;
	main_canvas.contex.oImageSmoothingEnabled = false;
	// Scrolltext
	font.initTile(6, 6, 32);
	scroll_canvas = new canvas(3200, 6);
	scroll_canvas.clear();
	var i, j, x = 0;
	for (i = 0 ; i < text.length ; i++) {
		for (j = 0 ; j < letter.length ; j++) {
			if (letter[j][0] === text[i]) {
				break;
			}
		}
		font.drawPart(scroll_canvas, x, 0, letter[j][1], letter[j][2], letter[j][3], 6);
		x += letter[j][3] + 1;
	}
	// Start anim
	anim_splash1();
}

function trigo_build() {
	for (var i = 0 ; i < lutLen ; i++) {
		var a = (i * 2 * Math.PI) * (1 / lutLen);
		lutSin[i] = 32767 * Math.sin(a);
		lutCos[i] = 32767 * Math.cos(a);
	}
}

function mod(v, m) {
	while (v < 0) v += m;
	return v % m;
}

function anim_splash1() {
	black_canvas = new canvas(screen_width * zoom, screen_height * zoom);
	black_canvas.fill('#000000');
	main_canvas.fill('#F3F5F2');
	if (iteration < 180) {
		requestAnimFrame(anim_splash1);
		if (iteration < 30) {
			splash1.draw(main_canvas, 32 * zoom, 35 * zoom, (iteration / 30), 0, zoom, zoom);
		} else if (30 <= iteration && iteration < 120) {
			splash1.draw(main_canvas, 32 * zoom, 35 * zoom, 1, 0, zoom, zoom);
		} else if (120 <= iteration && iteration < 180) {
			splash1.draw(main_canvas, 32 * zoom, 35 * zoom, 1, 0, zoom, zoom);
			black_canvas.draw(main_canvas, 0, 0, (iteration - 120) / 60, 0, zoom, zoom);
		}
	} else {
		requestAnimFrame(anim_splash2);
		iteration = -1;
		// Play sample
		player = new music('MK');
		player.LoadAndRun(basepath + 'splash.xm');
	}
	iteration++;
}

function anim_splash2() {
	main_canvas.fill('#442266');
	splash2.draw(main_canvas, 32 * zoom, 35 * zoom, 1, 0, zoom, zoom);
	// Bee
	bee_x += bee_dir;
	if (bee_x == 0)   bee_dir =  2;
	if (bee_x == 192) bee_dir = -2;
	var bee_y = 100 - 73 * Math.abs(Math.sin(iteration / 20));
	bee.draw(main_canvas, (32 + bee_x) * zoom, bee_y * zoom, 1, 0, zoom, zoom);
	// Progress bar
	progress_1 = iteration / 2;
	if (progress_1 > 320) progress_1 = 320;
	main_canvas.line(32 * zoom, 230 * zoom, (32 + progress_1) * zoom, 230 * zoom, zoom, '#000000');
	progress_2 = iteration / 4;
	if (progress_2 > 320) progress_2 = 320;
	main_canvas.line(32 * zoom, 230 * zoom, (32 + progress_2) * zoom, 230 * zoom, zoom, '#8888CC');
	if (progress_2 < 320) {
		requestAnimFrame(anim_splash2);
	} else {
		requestAnimFrame(anim_splash3);
		iteration = -1;
		// Stop sample
		player.loader['player'].stop();
	}
	iteration++;
}

function anim_splash3() {
	if (iteration < 120) {
		requestAnimFrame(anim_splash3);
		main_canvas.fill('#000000');
	} else {
		requestAnimFrame(anim);
		iteration = -1;
		// Mad Max SOS tune
		player = new music('YM');
		player.LoadAndRun(basepath + 'mad-max-sos.ym');                
	}
	iteration++;
}

function anim() {
	requestAnimFrame(anim);
	// Background
	main_canvas.fill('#224488');
	back.draw(main_canvas, 32 * zoom, 35 * zoom, 1, 0, zoom, zoom);
	// Scrolltext
	scroll_canvas.drawPart(
		main_canvas,
		32 * zoom, 230 * zoom,
		(iteration * 1.5) % (3200 - 320), 0,
		320, 6,
		1, 0, zoom, zoom
	);
	// Sprites
	draw_sprites();
	iteration++;
}

