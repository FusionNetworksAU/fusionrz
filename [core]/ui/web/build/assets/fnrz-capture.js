/*
 * Game-frame capture for the clothing thumbnail tool (shop /clothingshots).
 * Plain script, loaded by index.html beside the bundle; not part of it.
 *
 * The NUI can read the live game frame: a WebGL texture given the wrap-mode
 * sequence below is bound by CEF to the game's backbuffer (the same trick the
 * bundle's ped preview uses, which is why that panel is plain blue outside
 * the game -- the 1x1 blue placeholder). The game frame does not include the
 * NUI itself, so menus never end up in a capture.
 *
 * Message in:  { action: 'fnrzCapture', data: { id, crop: {x,y,w,h} as 0..1
 *                fractions of the screen, size, quality } }
 * Reply:       POST https://<resource>/fnrzCaptured { id, image } or { id, error }
 *
 * The backdrop the shop draws is pure green; it is keyed out to transparency
 * here so the thumbnails sit on whatever card colour the UI uses.
 */
(function () {
    'use strict';

    var VERTEX = [
        'attribute vec2 a_position;',
        'attribute vec2 a_texcoord;',
        'varying vec2 textureCoordinate;',
        'void main() {',
        '    gl_Position = vec4(a_position, 0.0, 1.0);',
        '    textureCoordinate = a_texcoord;',
        '}'
    ].join('\n');

    var FRAGMENT = [
        'precision mediump float;',
        'varying highp vec2 textureCoordinate;',
        'uniform sampler2D external_texture;',
        'void main() {',
        '    gl_FragColor = texture2D(external_texture, textureCoordinate);',
        '}'
    ].join('\n');

    var glCanvas = null;
    var gl = null;

    function resourceName() {
        return window.GetParentResourceName ? window.GetParentResourceName() : 'ui';
    }

    function reply(payload) {
        fetch('https://' + resourceName() + '/fnrzCaptured', {
            method: 'POST',
            headers: { 'Content-Type': 'application/json; charset=UTF-8' },
            body: JSON.stringify(payload)
        }).catch(function () {});
    }

    function setup() {
        if (gl) {
            return;
        }

        glCanvas = document.createElement('canvas');
        gl = glCanvas.getContext('webgl', {
            antialias: false, depth: false, stencil: false, alpha: false,
            preserveDrawingBuffer: true
        });

        if (!gl) {
            throw new Error('WebGL unavailable');
        }

        function shader(type, source) {
            var s = gl.createShader(type);
            gl.shaderSource(s, source);
            gl.compileShader(s);
            return s;
        }

        var program = gl.createProgram();
        gl.attachShader(program, shader(gl.VERTEX_SHADER, VERTEX));
        gl.attachShader(program, shader(gl.FRAGMENT_SHADER, FRAGMENT));
        gl.linkProgram(program);
        gl.useProgram(program);

        // The game-view texture: this exact parameter sequence is the hook.
        var texture = gl.createTexture();
        gl.bindTexture(gl.TEXTURE_2D, texture);
        gl.texImage2D(gl.TEXTURE_2D, 0, gl.RGBA, 1, 1, 0, gl.RGBA, gl.UNSIGNED_BYTE, new Uint8Array([0, 0, 255, 255]));
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MAG_FILTER, gl.NEAREST);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_MIN_FILTER, gl.NEAREST);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_S, gl.CLAMP_TO_EDGE);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.MIRRORED_REPEAT);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.REPEAT);
        gl.texParameterf(gl.TEXTURE_2D, gl.TEXTURE_WRAP_T, gl.CLAMP_TO_EDGE);

        var positions = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, positions);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([-1, -1, 1, -1, -1, 1, 1, 1]), gl.STATIC_DRAW);
        var aPosition = gl.getAttribLocation(program, 'a_position');
        gl.enableVertexAttribArray(aPosition);
        gl.vertexAttribPointer(aPosition, 2, gl.FLOAT, false, 0, 0);

        var texcoords = gl.createBuffer();
        gl.bindBuffer(gl.ARRAY_BUFFER, texcoords);
        gl.bufferData(gl.ARRAY_BUFFER, new Float32Array([0, 0, 1, 0, 0, 1, 1, 1]), gl.STATIC_DRAW);
        var aTexcoord = gl.getAttribLocation(program, 'a_texcoord');
        gl.enableVertexAttribArray(aTexcoord);
        gl.vertexAttribPointer(aTexcoord, 2, gl.FLOAT, false, 0, 0);
    }

    // Green backdrop -> transparent, with a soft edge so hair and fabric
    // outlines are not cut jagged. Green that dominates red and blue is key.
    function keyOutGreen(ctx, size) {
        var image = ctx.getImageData(0, 0, size, size);
        var px = image.data;

        for (var i = 0; i < px.length; i += 4) {
            var r = px[i], g = px[i + 1], b = px[i + 2];
            var other = Math.max(r, b);
            var excess = g - other;

            if (g > 60 && excess > 40) {
                // 40..110 excess fades from opaque to fully keyed.
                var alpha = Math.max(0, Math.min(1, 1 - (excess - 40) / 70));
                px[i + 3] = Math.round(px[i + 3] * alpha);
                // Pull the green spill out of edge pixels.
                px[i + 1] = Math.min(g, other + 10);
            }
        }

        ctx.putImageData(image, 0, 0);
    }

    function capture(data) {
        setup();

        var width = window.innerWidth;
        var height = window.innerHeight;

        glCanvas.width = width;
        glCanvas.height = height;
        gl.viewport(0, 0, width, height);

        var frames = 0;

        function frame() {
            try {
                gl.drawArrays(gl.TRIANGLE_STRIP, 0, 4);
                gl.finish();

                // A few frames so the texture is bound to a fresh game frame.
                if (++frames < 4) {
                    requestAnimationFrame(frame);
                    return;
                }

                var crop = data.crop || { x: 0, y: 0, w: 1, h: 1 };
                var size = data.size || 512;
                var out = document.createElement('canvas');
                out.width = size;
                out.height = size;
                var ctx = out.getContext('2d');

                ctx.drawImage(glCanvas,
                    crop.x * width, crop.y * height, crop.w * width, crop.h * height,
                    0, 0, size, size);

                keyOutGreen(ctx, size);

                reply({ id: data.id, image: out.toDataURL('image/webp', data.quality || 0.9) });
            } catch (err) {
                reply({ id: data.id, error: String(err && err.message || err) });
            }
        }

        requestAnimationFrame(frame);
    }

    window.addEventListener('message', function (event) {
        var msg = event.data;

        if (!msg || msg.action !== 'fnrzCapture' || !msg.data) {
            return;
        }

        try {
            capture(msg.data);
        } catch (err) {
            reply({ id: msg.data.id, error: String(err && err.message || err) });
        }
    });
})();
