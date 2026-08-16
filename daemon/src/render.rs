//! wgpu renderer shared by desktop and fullscreen modes.
//!
//! Resource-swap policy (matters for "no leaks when changing visualization"):
//! everything that depends on the *shader* lives in `Pipeline`, and everything
//! that depends on the *band count* lives in `BandBuffer`. Swapping a visual
//! drops the old `Pipeline` — shader module, bind group layout, bind group and
//! render pipeline all release together, because wgpu frees a resource once the
//! last handle is dropped. Nothing is cached per-visual, so N swaps cost the
//! same as one. The device, queue, surface and uniform buffer are created once
//! and reused.

use crate::config::{Config, Mode};
use crate::ipc::Frame;
use crate::visual::{self, MAX_PARAMS, Visual};
use anyhow::{Context, Result};
use bytemuck::{Pod, Zeroable};
use std::sync::Arc;
use tracing;

#[repr(C)]
#[derive(Copy, Clone, Debug, Pod, Zeroable)]
struct Uniforms {
    params: [f32; 4],
    view: [f32; 4],
    low: [f32; 4],
    high: [f32; 4],
    bg: [f32; 4],
    knobs: [f32; 4],
    knobs2: [f32; 4],
}

/// Everything tied to one visualization. Dropped wholesale on swap.
struct Pipeline {
    pipeline: wgpu::RenderPipeline,
    bind_group: wgpu::BindGroup,
    visual: Visual,
}

/// Storage buffer sized to the band count. Recreated only when that changes.
struct BandBuffer {
    buffer: wgpu::Buffer,
    len: usize,
}

pub struct Renderer {
    device: wgpu::Device,
    queue: wgpu::Queue,
    surface: wgpu::Surface<'static>,
    surface_config: wgpu::SurfaceConfiguration,
    uniform_buffer: wgpu::Buffer,
    bind_group_layout: wgpu::BindGroupLayout,
    bands: BandBuffer,
    peaks_buf: wgpu::Buffer,
    pipeline: Option<Pipeline>,
    cfg: Config,
    mode: Mode,
    start: std::time::Instant,
    /// Per-bar peak line carried across frames (for winamp-style peak-hold,
    /// e.g. the `fire` visual). Indexed by band; size tracks the band buffer.
    peaks: Vec<f32>,
    /// Cached band values from the last frame, reused to advance `peaks`.
    last_bands: Vec<f32>,
}

impl Renderer {
    pub fn new(
        target: Arc<dyn wgpu::WindowHandle + Send + Sync>,
        width: u32,
        height: u32,
        cfg: Config,
        mode: Mode,
    ) -> Result<Renderer> {
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor {
            // GL-only backend. Vulkan's swapchain acquire times out on this
            // Wayland/radv setup ("couldn't acquire next frame"), leaving the
            // window blank; GL presents reliably. The GL/EGL backend segfaults
            // when its EGL instance is dropped at shutdown (wgpu + Mesa +
            // Wayland bug) — client::run leaks the renderer to avoid that.
            backends: wgpu::Backends::GL,
            ..Default::default()
        });

        let surface = instance
            .create_surface(wgpu::SurfaceTarget::Window(Box::new(target)))
            .context("creating wgpu surface")?;

        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::LowPower,
            compatible_surface: Some(&surface),
            force_fallback_adapter: false,
        }))
        .context("no suitable GPU adapter")?;

        let (device, queue) = pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
            label: Some("omaviz-device"),
            required_features: wgpu::Features::empty(),
            // Use the adapter's real limits: downlevel_defaults() caps
            // textures at 2048px and panics on a 4K display.
            required_limits: adapter.limits(),
            memory_hints: wgpu::MemoryHints::MemoryUsage,
            experimental_features: wgpu::ExperimentalFeatures::disabled(),
            trace: wgpu::Trace::Off,
        }))
        .context("requesting GPU device")?;

        let caps = surface.get_capabilities(&adapter);
        let format = caps
            .formats
            .iter()
            .copied()
            .find(|f| f.is_srgb())
            .unwrap_or(caps.formats[0]);

        // The GL backend only advertises Opaque alpha on this compositor;
        // PostMultiplied/PreMultiplied are rejected at Surface::configure.
        // Opaque means the window background is not see-through (fine for a
        // visualizer) but present works reliably under GL + Fifo.
        let alpha_mode = wgpu::CompositeAlphaMode::Opaque;

        let surface_config = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            width: width.max(1),
            height: height.max(1),
            // Fifo is the only present mode guaranteed not to time out on
            // Wayland; AutoVsync/Vulkan would block on swapchain acquire.
            present_mode: wgpu::PresentMode::Fifo,
            alpha_mode,
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&device, &surface_config);

        let uniform_buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("omaviz-uniforms"),
            size: std::mem::size_of::<Uniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let bind_group_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("omaviz-bgl"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 2,
                    visibility: wgpu::ShaderStages::VERTEX_FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });

        let peaks_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("omaviz-peaks"),
            size: (cfg.bands(mode).max(1) * std::mem::size_of::<f32>()) as u64,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });

        let bands = BandBuffer::new(&device, cfg.bands(mode).max(1));
        let band_count = cfg.bands(mode).max(1);

        let mut r = Renderer {
            device,
            queue,
            surface,
            surface_config,
            uniform_buffer,
            bind_group_layout,
            bands,
            peaks_buf,
            pipeline: None,
            cfg,
            mode,
            start: std::time::Instant::now(),
            peaks: vec![0f32; band_count],
            last_bands: vec![0f32; band_count],
        };

        let want = r.cfg.mode(mode).visual.clone();
        r.set_visual(&want)?;
        Ok(r)
    }

    /// Swap the active visualization, releasing the previous one's GPU objects.
    pub fn set_visual(&mut self, name: &str) -> Result<()> {
        let Some(v) = visual::resolve_or_first(name) else {
            anyhow::bail!("no visualizations found in {:?}", visual::visuals_dir());
        };

        let src = visual::shader_source(&v)?;

        // Validate shader source before compiling for security
        visual::validate_shader_source(&src, &v.name)?;

        // Compile first: on a shader error keep the old pipeline running rather
        // than leaving the window blank.
        let module = self
            .device
            .create_shader_module(wgpu::ShaderModuleDescriptor {
                label: Some(&format!("omaviz-{}", v.name)),
                source: wgpu::ShaderSource::Wgsl(src.into()),
            });

        let layout = self
            .device
            .create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
                label: Some("omaviz-layout"),
                bind_group_layouts: &[&self.bind_group_layout],
                push_constant_ranges: &[],
            });

        let pipeline = self
            .device
            .create_render_pipeline(&wgpu::RenderPipelineDescriptor {
                label: Some("omaviz-pipeline"),
                layout: Some(&layout),
                vertex: wgpu::VertexState {
                    module: &module,
                    entry_point: Some("vs_main"),
                    buffers: &[],
                    compilation_options: Default::default(),
                },
                fragment: Some(wgpu::FragmentState {
                    module: &module,
                    entry_point: Some("fs_main"),
                    targets: &[Some(wgpu::ColorTargetState {
                        format: self.surface_config.format,
                        blend: Some(wgpu::BlendState::ALPHA_BLENDING),
                        write_mask: wgpu::ColorWrites::ALL,
                    })],
                    compilation_options: Default::default(),
                }),
                primitive: wgpu::PrimitiveState::default(),
                depth_stencil: None,
                multisample: wgpu::MultisampleState::default(),
                multiview: None,
                cache: None,
            });

        let bind_group = self.make_bind_group();

        // Assigning drops the old Pipeline here: shader module, pipeline and
        // bind group are released together.
        self.pipeline = Some(Pipeline {
            pipeline,
            bind_group,
            visual: v,
        });
        Ok(())
    }

    fn make_bind_group(&self) -> wgpu::BindGroup {
        self.device.create_bind_group(&wgpu::BindGroupDescriptor {
            label: Some("omaviz-bg"),
            layout: &self.bind_group_layout,
            entries: &[
                wgpu::BindGroupEntry {
                    binding: 0,
                    resource: self.uniform_buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 1,
                    resource: self.bands.buffer.as_entire_binding(),
                },
                wgpu::BindGroupEntry {
                    binding: 2,
                    resource: self.peaks_buf.as_entire_binding(),
                },
            ],
        })
    }

    /// Apply a reloaded config: swap the visual only when it actually changed,
    /// and resize the band buffer only when the count changed.
    pub fn apply_config(&mut self, cfg: Config) -> Result<()> {
        let visual_changed = cfg.mode(self.mode).visual != self.cfg.mode(self.mode).visual;
        let bands_changed = cfg.bands(self.mode).max(1) != self.bands.len;
        self.cfg = cfg;

        if bands_changed {
            self.bands = BandBuffer::new(&self.device, self.cfg.bands(self.mode).max(1));
            self.peaks_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("omaviz-peaks"),
                size: (self.cfg.bands(self.mode).max(1) * std::mem::size_of::<f32>()) as u64,
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            self.peaks = vec![0f32; self.cfg.bands(self.mode).max(1)];
            self.last_bands = vec![0f32; self.cfg.bands(self.mode).max(1)];
            // The bind group references the old buffers; rebuild it.
            if self.pipeline.is_some() {
                let bg = self.make_bind_group();
                if let Some(p) = self.pipeline.as_mut() {
                    p.bind_group = bg;
                }
            }
        }

        if visual_changed {
            let want = self.cfg.mode(self.mode).visual.clone();
            self.set_visual(&want)?;
        }
        Ok(())
    }

    pub fn resize(&mut self, width: u32, height: u32) {
        if width == 0 || height == 0 {
            return;
        }
        self.surface_config.width = width;
        self.surface_config.height = height;
        self.surface.configure(&self.device, &self.surface_config);
    }

    pub fn render(&mut self, frame: &Frame) -> Result<()> {
        let Some(p) = self.pipeline.as_ref() else {
            return Ok(());
        };

        // Band data: pad or truncate to the buffer length so a daemon/client
        // mismatch can never read out of bounds.
        let mut data = vec![0f32; self.bands.len];
        let n = frame.bands.len().min(self.bands.len);
        data[..n].copy_from_slice(&frame.bands[..n]);
        self.queue
            .write_buffer(&self.bands.buffer, 0, bytemuck::cast_slice(&data));

        let pal = self.cfg.resolved_palette();

        // Per-visual knob values, in declaration order.
        let mut knobs = [0f32; MAX_PARAMS];
        for (i, param) in p.visual.params.iter().take(MAX_PARAMS).enumerate() {
            knobs[i] = self.cfg.visual_param(&p.visual.name, param);
        }
        // Per-display *fit* knobs live in the mode's `extra` table (not the
        // visual's params) and are surfaced to shaders via knobs2[0..3] so a
        // visual can read them with k(4)/k(5)/k(6):
        //   k(4) = full_detail   (desktop/full: how much vertical room bars use)
        //   k(5) = full_quality  (circular visuals: supersample-ish factor)
        //   k(6) = mini_simplify (menu-bar: simplify the visual for tiny space)
        let extra = &self.cfg.mode(self.mode).extra;
        let fit = [
            extra.get("full_detail").copied().unwrap_or(1.0),
            extra.get("full_quality").copied().unwrap_or(1.5),
            extra.get("mini_simplify").copied().unwrap_or(0.0),
            0.0,
        ];

        // Advance the winamp-style peak line: each band holds its previous peak
        // and falls slowly, jumping up instantly when the new level is higher.
        // Written to the `peaks` storage buffer so shaders can sample it per-x.
        let fall = if p.visual.name == "fire" {
            self.cfg
                .visual_param("fire", &p.visual.params[4])
                .clamp(0.01, 0.5)
        } else {
            0.5
        };
        let len = self.peaks.len();
        for i in 0..len {
            let cur = frame.bands.get(i).copied().unwrap_or(0.0) * self.cfg.sensitivity(self.mode);
            let prev = self.last_bands.get(i).copied().unwrap_or(0.0);
            let peak = self.peaks[i];
            let target = cur.max(prev);
            self.peaks[i] = if target > peak {
                target
            } else {
                (peak - fall).max(target).max(0.0)
            };
            self.last_bands[i] = cur;
        }
        // Upload the peak line (same length as the bands buffer).
        self.queue
            .write_buffer(&self.peaks_buf, 0, bytemuck::cast_slice(&self.peaks));

        let u = Uniforms {
            params: [
                self.start.elapsed().as_secs_f32(),
                frame.energy,
                frame.beat,
                self.bands.len as f32,
            ],
            view: [
                self.surface_config.width as f32,
                self.surface_config.height as f32,
                self.cfg.sensitivity(self.mode),
                if pal.is_light { 1.0 } else { 0.0 },
            ],
            low: [pal.low[0], pal.low[1], pal.low[2], 1.0],
            high: [pal.high[0], pal.high[1], pal.high[2], 1.0],
            bg: pal.bg,
            knobs: [knobs[0], knobs[1], knobs[2], knobs[3]],
            // knobs2[0..3] = the per-display fit knobs (k(4)/k(5)/k(6)); any
            // visual-declared params beyond index 3 would also land here, but the
            // fit values are what shaders read via k(4..6).
            knobs2: fit,
        };
        self.queue
            .write_buffer(&self.uniform_buffer, 0, bytemuck::bytes_of(&u));

        let surface_texture = match self.surface.get_current_texture() {
            Ok(t) => t,
            Err(wgpu::SurfaceError::Outdated | wgpu::SurfaceError::Lost) => {
                tracing::warn!("Surface outdated/lost, reconfiguring...");
                self.surface.configure(&self.device, &self.surface_config);
                return Ok(());
            }
            Err(wgpu::SurfaceError::OutOfMemory) => {
                tracing::error!("GPU out of memory, attempting recovery");
                // Try to recover by waiting a bit
                std::thread::sleep(std::time::Duration::from_millis(100));
                return Ok(());
            }
            Err(e) => {
                tracing::error!("Surface error: {}", e);
                return Err(e.into());
            }
        };

        let view = surface_texture
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());

        let mut encoder = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor {
                label: Some("omaviz-encoder"),
            });
        {
            let mut pass = encoder.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("omaviz-pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    resolve_target: None,
                    depth_slice: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(if std::env::var("OMAVIZ_DEBUG_FILL").is_ok() {
                            wgpu::Color { r: 0.9, g: 0.2, b: 0.5, a: 1.0 }
                        } else {
                            wgpu::Color {
                                r: pal.bg[0] as f64,
                                g: pal.bg[1] as f64,
                                b: pal.bg[2] as f64,
                                a: pal.bg[3] as f64,
                            }
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(&p.pipeline);
            pass.set_bind_group(0, &p.bind_group, &[]);
            pass.draw(0..3, 0..1);
        }

        self.queue.submit(Some(encoder.finish()));
        surface_texture.present();
        Ok(())
    }
}

impl BandBuffer {
    fn new(device: &wgpu::Device, len: usize) -> BandBuffer {
        let buffer = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("omaviz-bands"),
            size: (len * std::mem::size_of::<f32>()) as u64,
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        BandBuffer { buffer, len }
    }
}
