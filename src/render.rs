//! wgpu renderer shared by desktop and fullscreen modes.

use crate::config::{Config, Mode};
use crate::ipc::Frame;
use anyhow::{Context, Result};
use bytemuck::{Pod, Zeroable};
use std::sync::{Arc, Mutex};
use wgpu::util::DeviceExt;

#[repr(C)]
#[derive(Copy, Clone, Pod, Zeroable, Default)]
struct Uniforms {
    params: [f32; 4], // time, energy, beat, n_bands
    view: [f32; 4],   // width, height, sensitivity, _
    low: [f32; 4],
    high: [f32; 4],
    bg: [f32; 4],
}

pub struct Renderer {
    device: wgpu::Device,
    queue: wgpu::Queue,
    surface: wgpu::Surface<'static>,
    surface_cfg: wgpu::SurfaceConfiguration,
    pipeline: wgpu::RenderPipeline,
    bind_group: wgpu::BindGroup,
    bind_layout: wgpu::BindGroupLayout,
    uniform_buf: wgpu::Buffer,
    band_buf: wgpu::Buffer,
    band_capacity: usize,
    format: wgpu::TextureFormat,
    uniforms: Uniforms,
}

/// Load a visual's WGSL, prepending the shared uniform/vertex preamble.
pub fn load_shader_source(visual: &str) -> Result<String> {
    let dirs = visual_dirs();
    let common = read_first(&dirs, "_common.wgsl")
        .context("missing _common.wgsl in any visuals directory")?;
    let body = read_first(&dirs, &format!("{visual}.wgsl"))
        .with_context(|| format!("unknown visualization '{visual}'"))?;
    Ok(format!("{common}\n{body}"))
}

pub fn visual_dirs() -> Vec<std::path::PathBuf> {
    let mut v = vec![crate::config::config_dir().join("visuals")];
    if let Ok(exe) = std::env::current_exe() {
        // ../../visuals relative to target/<profile>/omaviz for dev runs
        if let Some(p) = exe
            .parent()
            .and_then(|p| p.parent())
            .and_then(|p| p.parent())
        {
            v.push(p.join("visuals"));
        }
    }
    v.push(std::path::PathBuf::from("visuals"));
    v.push(std::path::PathBuf::from("/usr/share/omaviz/visuals"));
    v
}

fn read_first(dirs: &[std::path::PathBuf], name: &str) -> Option<String> {
    dirs.iter()
        .map(|d| d.join(name))
        .find_map(|p| std::fs::read_to_string(p).ok())
}

/// List available visualization names (for the settings panel).
pub fn list_visuals() -> Vec<String> {
    let mut out = Vec::new();
    for d in visual_dirs() {
        let Ok(rd) = std::fs::read_dir(&d) else {
            continue;
        };
        for e in rd.flatten() {
            let p = e.path();
            if p.extension().and_then(|s| s.to_str()) != Some("wgsl") {
                continue;
            }
            let Some(stem) = p.file_stem().and_then(|s| s.to_str()) else {
                continue;
            };
            if stem.starts_with('_') {
                continue;
            }
            if !out.iter().any(|s: &String| s == stem) {
                out.push(stem.to_string());
            }
        }
    }
    out.sort();
    out
}

impl Renderer {
    pub fn new(window: Arc<winit::window::Window>, cfg: &Config, mode: Mode) -> Result<Renderer> {
        let size = window.inner_size();
        let instance = wgpu::Instance::new(&wgpu::InstanceDescriptor::default());
        let surface = instance.create_surface(window.clone())?;
        let adapter = pollster::block_on(instance.request_adapter(&wgpu::RequestAdapterOptions {
            power_preference: wgpu::PowerPreference::LowPower,
            compatible_surface: Some(&surface),
            force_fallback_adapter: false,
        }))
        .context("no suitable GPU adapter")?;

        let (device, queue) =
            pollster::block_on(adapter.request_device(&wgpu::DeviceDescriptor {
                label: Some("omaviz-device"),
                required_features: wgpu::Features::empty(),
                // Use what the adapter actually offers: downlevel_defaults caps
                // textures at 2048px, which fails on 4K displays / tiled WMs.
                required_limits:
                    wgpu::Limits::downlevel_defaults().using_resolution(adapter.limits()),
                memory_hints: wgpu::MemoryHints::MemoryUsage,
                experimental_features: wgpu::ExperimentalFeatures::disabled(),
                trace: wgpu::Trace::Off,
            }))?;

        let caps = surface.get_capabilities(&adapter);
        let format = caps
            .formats
            .iter()
            .copied()
            .find(|f| f.is_srgb())
            .unwrap_or(caps.formats[0]);

        let surface_cfg = wgpu::SurfaceConfiguration {
            usage: wgpu::TextureUsages::RENDER_ATTACHMENT,
            format,
            width: size.width.max(1),
            height: size.height.max(1),
            // Fifo = vsync = no wasted frames. Never use Mailbox here.
            present_mode: wgpu::PresentMode::Fifo,
            alpha_mode: caps.alpha_modes[0],
            view_formats: vec![],
            desired_maximum_frame_latency: 2,
        };
        surface.configure(&device, &surface_cfg);

        let band_capacity = cfg.bands.max(1);
        let uniform_buf = device.create_buffer(&wgpu::BufferDescriptor {
            label: Some("omaviz-uniforms"),
            size: std::mem::size_of::<Uniforms>() as u64,
            usage: wgpu::BufferUsages::UNIFORM | wgpu::BufferUsages::COPY_DST,
            mapped_at_creation: false,
        });
        let band_buf = device.create_buffer_init(&wgpu::util::BufferInitDescriptor {
            label: Some("omaviz-bands"),
            contents: bytemuck::cast_slice(&vec![0f32; band_capacity]),
            usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
        });

        let bind_layout = device.create_bind_group_layout(&wgpu::BindGroupLayoutDescriptor {
            label: Some("omaviz-bgl"),
            entries: &[
                wgpu::BindGroupLayoutEntry {
                    binding: 0,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Uniform,
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
                wgpu::BindGroupLayoutEntry {
                    binding: 1,
                    visibility: wgpu::ShaderStages::FRAGMENT,
                    ty: wgpu::BindingType::Buffer {
                        ty: wgpu::BufferBindingType::Storage { read_only: true },
                        has_dynamic_offset: false,
                        min_binding_size: None,
                    },
                    count: None,
                },
            ],
        });

        let bind_group = make_bind_group(&device, &bind_layout, &uniform_buf, &band_buf);

        let visual = &cfg.mode(mode).visual;
        let pipeline = build_pipeline(&device, &bind_layout, format, visual)?;

        let p = &cfg.palette;
        let uniforms = Uniforms {
            params: [0.0, 0.0, 0.0, band_capacity as f32],
            view: [size.width as f32, size.height as f32, cfg.sensitivity, 0.0],
            low: [p.low[0], p.low[1], p.low[2], 1.0],
            high: [p.high[0], p.high[1], p.high[2], 1.0],
            bg: p.bg,
        };

        Ok(Renderer {
            device,
            queue,
            surface,
            surface_cfg,
            pipeline,
            bind_group,
            bind_layout,
            uniform_buf,
            band_buf,
            band_capacity,
            format,
            uniforms,
        })
    }

    pub fn resize(&mut self, w: u32, h: u32) {
        if w == 0 || h == 0 {
            return;
        }
        self.surface_cfg.width = w;
        self.surface_cfg.height = h;
        self.surface.configure(&self.device, &self.surface_cfg);
        self.uniforms.view[0] = w as f32;
        self.uniforms.view[1] = h as f32;
    }

    /// Swap the fragment shader at runtime (config hot-reload).
    pub fn set_visual(&mut self, visual: &str) -> Result<()> {
        self.pipeline = build_pipeline(&self.device, &self.bind_layout, self.format, visual)?;
        Ok(())
    }

    pub fn apply_config(&mut self, cfg: &Config) {
        let p = &cfg.palette;
        self.uniforms.low = [p.low[0], p.low[1], p.low[2], 1.0];
        self.uniforms.high = [p.high[0], p.high[1], p.high[2], 1.0];
        self.uniforms.bg = p.bg;
        self.uniforms.view[2] = cfg.sensitivity;
    }

    pub fn render(&mut self, frame: &Frame, time: f32) -> Result<()> {
        // Grow the band storage buffer if the daemon changed band count.
        if frame.bands.len() > self.band_capacity {
            self.band_capacity = frame.bands.len();
            self.band_buf = self.device.create_buffer(&wgpu::BufferDescriptor {
                label: Some("omaviz-bands"),
                size: (self.band_capacity * 4) as u64,
                usage: wgpu::BufferUsages::STORAGE | wgpu::BufferUsages::COPY_DST,
                mapped_at_creation: false,
            });
            self.bind_group = make_bind_group(
                &self.device,
                &self.bind_layout,
                &self.uniform_buf,
                &self.band_buf,
            );
        }

        self.uniforms.params = [time, frame.energy, frame.beat, frame.bands.len() as f32];
        self.queue
            .write_buffer(&self.uniform_buf, 0, bytemuck::bytes_of(&self.uniforms));
        if !frame.bands.is_empty() {
            self.queue
                .write_buffer(&self.band_buf, 0, bytemuck::cast_slice(&frame.bands));
        }

        let surface_tex = match self.surface.get_current_texture() {
            Ok(t) => t,
            Err(wgpu::SurfaceError::Lost | wgpu::SurfaceError::Outdated) => {
                self.surface.configure(&self.device, &self.surface_cfg);
                return Ok(());
            }
            Err(e) => return Err(e.into()),
        };
        let view = surface_tex
            .texture
            .create_view(&wgpu::TextureViewDescriptor::default());
        let mut enc = self
            .device
            .create_command_encoder(&wgpu::CommandEncoderDescriptor { label: None });
        {
            let mut pass = enc.begin_render_pass(&wgpu::RenderPassDescriptor {
                label: Some("omaviz-pass"),
                color_attachments: &[Some(wgpu::RenderPassColorAttachment {
                    view: &view,
                    depth_slice: None,
                    resolve_target: None,
                    ops: wgpu::Operations {
                        load: wgpu::LoadOp::Clear(wgpu::Color {
                            r: self.uniforms.bg[0] as f64,
                            g: self.uniforms.bg[1] as f64,
                            b: self.uniforms.bg[2] as f64,
                            a: self.uniforms.bg[3] as f64,
                        }),
                        store: wgpu::StoreOp::Store,
                    },
                })],
                depth_stencil_attachment: None,
                timestamp_writes: None,
                occlusion_query_set: None,
            });
            pass.set_pipeline(&self.pipeline);
            pass.set_bind_group(0, &self.bind_group, &[]);
            pass.draw(0..3, 0..1);
        }
        self.queue.submit(Some(enc.finish()));
        surface_tex.present();
        Ok(())
    }
}

fn make_bind_group(
    device: &wgpu::Device,
    layout: &wgpu::BindGroupLayout,
    uniform: &wgpu::Buffer,
    bands: &wgpu::Buffer,
) -> wgpu::BindGroup {
    device.create_bind_group(&wgpu::BindGroupDescriptor {
        label: Some("omaviz-bg"),
        layout,
        entries: &[
            wgpu::BindGroupEntry {
                binding: 0,
                resource: uniform.as_entire_binding(),
            },
            wgpu::BindGroupEntry {
                binding: 1,
                resource: bands.as_entire_binding(),
            },
        ],
    })
}

fn build_pipeline(
    device: &wgpu::Device,
    layout: &wgpu::BindGroupLayout,
    format: wgpu::TextureFormat,
    visual: &str,
) -> Result<wgpu::RenderPipeline> {
    let src = load_shader_source(visual)?;
    let shader = device.create_shader_module(wgpu::ShaderModuleDescriptor {
        label: Some(visual),
        source: wgpu::ShaderSource::Wgsl(src.into()),
    });
    let pl = device.create_pipeline_layout(&wgpu::PipelineLayoutDescriptor {
        label: None,
        bind_group_layouts: &[layout],
        push_constant_ranges: &[],
    });
    Ok(
        device.create_render_pipeline(&wgpu::RenderPipelineDescriptor {
            label: Some("omaviz-pipeline"),
            layout: Some(&pl),
            vertex: wgpu::VertexState {
                module: &shader,
                entry_point: Some("vs_main"),
                buffers: &[],
                compilation_options: Default::default(),
            },
            fragment: Some(wgpu::FragmentState {
                module: &shader,
                entry_point: Some("fs_main"),
                targets: &[Some(format.into())],
                compilation_options: Default::default(),
            }),
            primitive: wgpu::PrimitiveState::default(),
            depth_stencil: None,
            multisample: wgpu::MultisampleState::default(),
            multiview: None,
            cache: None,
        }),
    )
}

/// Latest-frame slot shared between the IPC reader thread and the render loop.
pub type SharedFrame = Arc<Mutex<Frame>>;
