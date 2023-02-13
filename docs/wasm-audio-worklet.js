// in own process, cannot directly interact with browser js
class ZigSynthWorkletProcessor extends AudioWorkletProcessor {

	zig_machine = null;
    mainBuffer = null;
    indexFloatCopyBuffer = 0;
    indexMainBuffer = 0;
    running = true;
    
    constructor(options) {
		super();

		console.log("constructor with options: ");
		console.log(options.processorOptions);
		// set instance
		// this.zig_machine = options.processorOptions.zig_machine;
		// this.memory = options.processorOptions.zig_memory;
		// this.sfxBuffer = this.zig_machine.generateAudio;
		// this.u8ArrayToF32Array = this.zig_machine.u8ArrayToF32Array;		

		this.port.onmessage = async function (event) {

			if (event.data == 'stop') {

				console.log("On message: stop");
				this.running = false;
			}
		};
		this.port.onmessage = this.port.onmessage.bind(this);
		this.port.postMessage('ready');
		this.running = true;
    }

	allocateTo(alloced, size) {
		const mod = alloced % size;
		if (mod != 0){
			alloced += size - mod;
		}
		return alloced;
	}
		
    initFloatCopyBuffer(samplesRequired){
		let allocatorIndex = this.mainBuffer.byteOffset + this.mainBuffer.length;

		allocatorIndex = this.allocateTo(allocatorIndex, 4);
		this.floatCopyBuffer = new Float32Array(this.memory.buffer, allocatorIndex, samplesRequired);
    }

    process(inputs, outputs, parameters) {
		if(!this.memory){
			return this.running;
		}

		// audio buffer is 128 bytes
		const outLen = outputs[0][0].length;

		if (!this.mainBuffer || outLen > this.mainBuffer.length) {
			let allocatorIndex = this.allocateTo(0, 2);
			this.mainBuffer = new Uint8Array(this.memory.buffer, allocatorIndex, outLen);
		}
		
		if (!this.floatCopyBuffer || outLen > this.floatCopyBuffer.length) {
			this.initFloatCopyBuffer(outLen);
		}

		this.indexFloatCopyBuffer = 0;
		let copied = -1;
		while(copied != 0 && this.indexFloatCopyBuffer < this.floatCopyBuffer.length) {
			if (this.indexMainBuffer == 0) {
				this.sfxBuffer(this.mainBuffer.byteOffset, this.mainBuffer.length);
				console.log(this.mainBuffer);
			}

			copied = this.u8ArrayToF32Array(
				this.mainBuffer.byteOffset + this.indexMainBuffer,
				this.mainBuffer.length - this.indexMainBuffer,
				this.floatCopyBuffer.byteOffset + this.indexFloatCopyBuffer * 4,
				this.floatCopyBuffer.length - this.indexFloatCopyBuffer);

			this.indexFloatCopyBuffer += copied;
			this.indexMainBuffer += copied;
			if (this.indexMainBuffer >= this.mainBuffer.length) {
				this.indexMainBuffer = 0;
			}
		}

		for (let channel = 0; channel < outputs.length; channel++) {
			const outputChannel = outputs[channel];
			// no clue why outputchannel is an array of float arrays?
			outputChannel[0].set(this.floatCopyBuffer);
		}

		return this.running;
    }
}

registerProcessor('zig-synth-worklet-processor', ZigSynthWorkletProcessor);
