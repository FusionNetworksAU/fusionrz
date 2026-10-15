/*
	Shared by every lobby backdrop in this folder. Each backdrop is a page
	rendered into a DUI and painted onto the quad behind the podium
	(main.lua drawBackdropThread), so it is a texture in the world.

	Drawn at 1920x1096 (config duiResolution). Only part of it is on screen at
	the podium camera's zoom:
	  visible area      x 486-1584, y 288-907
	  party             x 860-990, y 420-770, feet at ~(930, 770)
	  menu covers       top bar y 288-340, info box x 1276-1561 y 362-411,
	                    queue panel x 1361-1584 y 689-907, chat x 486-620 y 860-890

	Rules that keep it cheap: scenery is static SVG, painted once; only small
	things animate, on one canvas; no CSS filters (blur on a texture this size
	cost ~45 fps).
*/
(function () {
	var SVG_NS = 'http://www.w3.org/2000/svg';
	var W = 1920;
	var H = 1096;

	// Seeded so the scenery is the same every time the lobby opens.
	var seed = 7;

	function rand() {
		seed = (seed * 16807) % 2147483647;
		return (seed - 1) / 2147483646;
	}

	function el(name, attrs, parent) {
		var node = document.createElementNS(SVG_NS, name);

		for (var key in attrs) {
			node.setAttribute(key, attrs[key]);
		}

		if (parent) {
			parent.appendChild(node);
		}

		return node;
	}

	// A pine: stacked tiers, needles in `colour` with `snow` on each tier
	// (pass null for a bare tree).
	function pine(parent, x, base, height, colour, snow) {
		var width = height * 0.42;
		var tiers = 4;

		el('rect', { x: x - height * 0.025, y: base - height * 0.12, width: height * 0.05, height: height * 0.12, fill: '#24160f' }, parent);

		for (var t = 0; t < tiers; t++) {
			var top = base - height + t * height * 0.2;
			var bottom = base - height * 0.1 - (tiers - 1 - t) * height * 0.13;
			var half = width * (0.45 + t * 0.2) / 2;

			el('path', { d: 'M' + x + ' ' + top + ' L' + (x + half) + ' ' + bottom + ' L' + (x - half) + ' ' + bottom + ' Z', fill: colour }, parent);

			if (snow) {
				el('path', {
					d: 'M' + x + ' ' + top +
						' L' + (x + half * 0.55) + ' ' + (top + (bottom - top) * 0.55) +
						' Q ' + x + ' ' + (top + (bottom - top) * 0.42) + ' ' + (x - half * 0.55) + ' ' + (top + (bottom - top) * 0.55) + ' Z',
					fill: snow
				}, parent);
				el('path', {
					d: 'M' + (x - half) + ' ' + bottom + ' Q ' + x + ' ' + (bottom - 8) + ' ' + (x + half) + ' ' + bottom + ' Z',
					fill: snow, opacity: 0.85
				}, parent);
			}
		}
	}

	// Static stars into an SVG group; every `twinkleEvery`th one is returned
	// to be twinkled on the canvas instead.
	function stars(parent, count, area, twinkleEvery) {
		var twinklers = [];

		for (var i = 0; i < count; i++) {
			var x = area.x + rand() * area.w;
			var y = area.y + rand() * area.h;
			var r = 0.6 + rand() * 1.6;

			if (twinkleEvery && i % twinkleEvery === 0) {
				twinklers.push({ x: x, y: y, r: r + 0.6, phase: rand() * Math.PI * 2, speed: 0.8 + rand() * 1.6 });
			} else {
				el('circle', { cx: x, cy: y, r: r, fill: '#efe8ff', opacity: (0.3 + rand() * 0.6).toFixed(2) }, parent);
			}
		}

		return twinklers;
	}

	function drawTwinkle(ctx, twinklers, time, colour) {
		ctx.fillStyle = colour || '#f6f0ff';

		for (var s = 0; s < twinklers.length; s++) {
			var star = twinklers[s];
			ctx.globalAlpha = 0.35 + 0.65 * (0.5 + 0.5 * Math.sin(time * star.speed + star.phase));
			ctx.beginPath();
			ctx.arc(star.x, star.y, star.r, 0, Math.PI * 2);
			ctx.fill();
		}

		ctx.globalAlpha = 1;
	}

	// Falling particles in three depths: far ones small and slow, near ones
	// big and fast. Snow by default; `rise` makes embers/sparks go up.
	function makeFall(options) {
		options = options || {};

		var layers = options.layers || [
			{ count: 220, size: [0.8, 1.6], speed: [25, 45], alpha: 0.55 },
			{ count: 140, size: [1.6, 2.8], speed: [45, 75], alpha: 0.75 },
			{ count: 60, size: [3.0, 4.6], speed: [80, 120], alpha: 0.9 }
		];
		var colour = options.colour || '#ffffff';
		var wind = options.wind === undefined ? 12 : options.wind;
		var dir = options.rise ? -1 : 1;
		var minX = options.minX || 0;
		var spanX = (options.maxX || W) - minX;
		var flakes = [];

		layers.forEach(function (layer, depth) {
			for (var n = 0; n < layer.count; n++) {
				flakes.push({
					x: minX + Math.random() * spanX,
					y: Math.random() * H,
					r: layer.size[0] + Math.random() * (layer.size[1] - layer.size[0]),
					vy: layer.speed[0] + Math.random() * (layer.speed[1] - layer.speed[0]),
					sway: 10 + Math.random() * 25 * (depth + 1),
					phase: Math.random() * Math.PI * 2,
					alpha: layer.alpha * (0.6 + Math.random() * 0.4)
				});
			}
		});

		// One soft dot, drawn once and stamped for every flake: no hard edge,
		// so the snow looks out of focus like the scenery behind it.
		var sprite = document.createElement('canvas');
		sprite.width = sprite.height = 32;
		var sctx = sprite.getContext('2d');
		var soft = sctx.createRadialGradient(16, 16, 0, 16, 16, 16);
		soft.addColorStop(0, colour);
		soft.addColorStop(0.35, colour);
		soft.addColorStop(1, 'rgba(255, 255, 255, 0)');
		sctx.fillStyle = soft;
		sctx.fillRect(0, 0, 32, 32);

		return function (ctx, dt, time) {
			for (var k = 0; k < flakes.length; k++) {
				var flake = flakes[k];
				flake.y += flake.vy * dt * dir;
				flake.phase += dt * 0.8;

				if (dir > 0 && flake.y > H + 6) {
					flake.y = -6;
					flake.x = minX + Math.random() * spanX;
				} else if (dir < 0 && flake.y < -6) {
					flake.y = H + 6;
					flake.x = minX + Math.random() * spanX;
				}

				var x = flake.x + Math.sin(flake.phase) * flake.sway + (time * wind) % W;
				x = ((x % W) + W) % W;

				// Sprite is twice the flake's radius across its solid core.
				var size = flake.r * 3.2;
				ctx.globalAlpha = flake.alpha;
				ctx.drawImage(sprite, x - size / 2, flake.y - size / 2, size, size);
			}

			ctx.globalAlpha = 1;
		};
	}

	// Warm flickering glow, additive, for windows, lanterns and fires.
	function glow(ctx, x, y, r, rgb, alpha) {
		var g = ctx.createRadialGradient(x, y, 0, x, y, r);
		g.addColorStop(0, 'rgba(' + rgb + ', ' + alpha.toFixed(3) + ')');
		g.addColorStop(1, 'rgba(' + rgb + ', 0)');

		ctx.globalCompositeOperation = 'lighter';
		ctx.fillStyle = g;
		ctx.fillRect(x - r, y - r, r * 2, r * 2);
		ctx.globalCompositeOperation = 'source-over';
	}

	// Chimney smoke: call every frame with the chimney top.
	function makeSmoke(x, y, colour) {
		var puffs = [];
		var timer = 0;

		return function (ctx, dt) {
			timer -= dt;

			if (timer <= 0) {
				timer = 0.35;
				puffs.push({ x: x, y: y, r: 8, life: 0 });
			}

			ctx.fillStyle = colour || '#d9d0ee';

			for (var p = puffs.length - 1; p >= 0; p--) {
				var puff = puffs[p];
				puff.life += dt;
				puff.y -= 22 * dt;
				puff.x += (14 + 6 * Math.sin(puff.life * 1.3)) * dt;
				puff.r += 12 * dt;

				var fade = 1 - puff.life / 6;

				if (fade <= 0) {
					puffs.splice(p, 1);
					continue;
				}

				// Faint and fast-growing so the puffs blend into a wisp rather
				// than reading as a stack of circles.
				ctx.globalAlpha = 0.09 * fade * Math.min(puff.life * 2, 1);
				ctx.beginPath();
				ctx.arc(puff.x, puff.y, puff.r, 0, Math.PI * 2);
				ctx.fill();
			}

			ctx.globalAlpha = 1;
		};
	}

	// Makes the flat vector scenery read like a photo taken behind the party:
	// out of focus (the sharp ped in front is the subject), colours pulled
	// back a little, and a fine film grain over it. Applied to the first
	// <svg> only, once; it is static, so the blur is rasterised a single time
	// rather than every frame like the old CSS-animated blur was.
	function photoTreatment() {
		var svg = document.querySelector('svg');

		if (!svg || svg.getAttribute('data-photo')) {
			return;
		}

		svg.setAttribute('data-photo', '1');

		var defs = svg.querySelector('defs') || el('defs', {}, svg);
		var lens = el('filter', { id: 'lens', x: '-5%', y: '-5%', width: '110%', height: '110%' }, defs);
		el('feGaussianBlur', { stdDeviation: '3.2', result: 'soft' }, lens);
		el('feColorMatrix', { type: 'saturate', values: '0.82' }, lens);

		var grain = el('filter', { id: 'grain', x: '0', y: '0', width: '100%', height: '100%' }, defs);
		el('feTurbulence', { type: 'fractalNoise', baseFrequency: '0.9', numOctaves: '2', seed: '3', stitchTiles: 'stitch' }, grain);
		el('feColorMatrix', { type: 'saturate', values: '0' }, grain);

		var scene = el('g', { filter: 'url(#lens)' });
		var nodes = Array.prototype.slice.call(svg.childNodes);

		for (var i = 0; i < nodes.length; i++) {
			if (nodes[i] !== defs) {
				scene.appendChild(nodes[i]);
			}
		}

		svg.appendChild(scene);
		el('rect', { width: W, height: H, filter: 'url(#grain)', opacity: '0.07', style: 'mix-blend-mode: overlay' }, svg);
	}

	// Starts the animation loop on the page's <canvas id="fx">. `draw` gets
	// (ctx, dt, time) in 1920x1096 coordinates. main.lua pauses the page while
	// the lobby is closed, so the DUI does not keep animating in the background.
	function run(draw) {
		photoTreatment();

		var canvas = document.getElementById('fx');
		var ctx = canvas.getContext('2d');
		var scale = 1;

		function resize() {
			canvas.width = window.innerWidth;
			canvas.height = window.innerHeight;
			scale = Math.max(canvas.width / W, canvas.height / H);
		}

		resize();
		window.addEventListener('resize', resize);

		var running = true;
		var last = performance.now();
		var time = 0;

		function frame(now) {
			if (!running) {
				return;
			}

			var dt = Math.min((now - last) / 1000, 0.1);
			last = now;
			time += dt;

			ctx.setTransform(1, 0, 0, 1, 0, 0);
			ctx.clearRect(0, 0, canvas.width, canvas.height);
			ctx.setTransform(scale, 0, 0, scale, (canvas.width - W * scale) / 2, (canvas.height - H * scale) / 2);

			draw(ctx, dt, time);

			ctx.globalAlpha = 1;
			requestAnimationFrame(frame);
		}

		requestAnimationFrame(frame);

		window.addEventListener('message', function (event) {
			var data = event.data;

			if (typeof data === 'string') {
				try { data = JSON.parse(data); } catch (e) { return; }
			}

			if (!data || data.type !== 'setPaused') {
				return;
			}

			if (data.paused) {
				running = false;
			} else if (!running) {
				running = true;
				last = performance.now();
				requestAnimationFrame(frame);
			}
		});
	}

	window.Backdrop = {
		W: W,
		H: H,
		rand: rand,
		el: el,
		pine: pine,
		stars: stars,
		drawTwinkle: drawTwinkle,
		makeFall: makeFall,
		makeSmoke: makeSmoke,
		glow: glow,
		run: run
	};
})();
