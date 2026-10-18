//! mint-macos-apfs-espacio: el tamaño y el espacio libre de un contenedor APFS, en
//! solo lectura. fsapfsmount no responde statfs (df da 0) y libfsapfs no expone el
//! espacio usado (libfsapfs_volume_get_size da 0); esto lo lee del contenedor mismo.
//!
//! Cómo, según la referencia de APFS de Apple (Apple File System Reference, 2020):
//!   1. nx_superblock en el bloque 0: tamaño de bloque, número de bloques y dónde
//!      está el área de checkpoints.
//!   2. El nx_superblock más nuevo del área de descriptores (el de xid mayor con su
//!      checksum Fletcher-64 bien): el del bloque 0 puede estar viejo.
//!   3. Su checkpoint map dice en qué bloque físico está el space manager
//!      (nx_spaceman_oid, un objeto efímero).
//!   4. spaceman_phys: sm_dev[SD_MAIN].sm_free_count son los bloques libres.
//! Libre = sm_free_count × bloque. Es lo que la Mac llama «available» del contenedor,
//! compartido por todos sus volúmenes. Como en Linux se monta en solo lectura, no
//! cambia mientras está montado: medirlo una vez al montar es exacto.
//!
//!     mint-macos-apfs-espacio DISPOSITIVO              JSON en la salida
//!     mint-macos-apfs-espacio DISPOSITIVO --guardar    y además en
//!                                     /run/mint-macos/apfs/<uuid del contenedor>.json
//!
//! Lo llama apfs/mount.fsapfs antes de montar (como root). No es un dato del arranque
//! sino de cada montaje: por eso va aparte de equipo.json (ver settings/LEEME.md).

use std::fs::{self, File};
use std::io::{Read, Seek, SeekFrom};
use std::os::unix::fs::PermissionsExt;
use std::path::Path;
use std::process::exit;

const NX_MAGIC: &[u8; 4] = b"NXSB";
const TIPO_NX_SUPERBLOCK: u32 = 0x01;
const TIPO_CHECKPOINT_MAP: u32 = 0x0c;
const TIPO_SPACEMAN: u32 = 0x05;

fn u32_en(b: &[u8], i: usize) -> u32 {
    u32::from_le_bytes(b[i..i + 4].try_into().unwrap())
}
fn u64_en(b: &[u8], i: usize) -> u64 {
    u64::from_le_bytes(b[i..i + 8].try_into().unwrap())
}

/// Fletcher-64 de APFS sobre el bloque sin sus 8 primeros bytes (el checksum mismo).
pub fn fletcher64(b: &[u8]) -> u64 {
    const M: u64 = 0xffff_ffff;
    let (mut s1, mut s2) = (0u64, 0u64);
    for c in b[8..].chunks_exact(4) {
        s1 = (s1 + u32::from_le_bytes(c.try_into().unwrap()) as u64) % M;
        s2 = (s2 + s1) % M;
    }
    let bajo = M - ((s1 + s2) % M);
    let alto = M - ((s1 + bajo) % M);
    (alto << 32) | bajo
}

fn valido(b: &[u8]) -> bool {
    b.len() >= 32 && u64_en(b, 0) == fletcher64(b)
}

fn tipo(b: &[u8]) -> u32 {
    u32_en(b, 24) & 0x0000_ffff
}

#[derive(Debug, PartialEq)]
pub struct Espacio {
    pub uuid: String,
    pub bloque: u32,
    pub total: u64,
    pub libre: u64,
    pub xid: u64,
}

/// Lee bloques de un dispositivo o de una imagen.
pub trait Disco {
    fn bloque(&mut self, n: u64, tam: u32) -> Option<Vec<u8>>;
}

impl Disco for File {
    fn bloque(&mut self, n: u64, tam: u32) -> Option<Vec<u8>> {
        let mut b = vec![0u8; tam as usize];
        self.seek(SeekFrom::Start(n.checked_mul(tam as u64)?)).ok()?;
        self.read_exact(&mut b).ok()?;
        Some(b)
    }
}

fn uuid(b: &[u8]) -> String {
    let h: String = b.iter().map(|x| format!("{x:02x}")).collect();
    format!("{}-{}-{}-{}-{}", &h[0..8], &h[8..12], &h[12..16], &h[16..20], &h[20..32])
}

pub fn leer(d: &mut impl Disco) -> Result<Espacio, String> {
    // 1. El bloque 0, leído con 4096 (el tamaño de bloque de casi todo APFS) y vuelto a
    //    leer con el suyo si es otro.
    let b0 = d.bloque(0, 4096).ok_or("no se lee el bloque 0")?;
    if &b0[32..36] != NX_MAGIC {
        return Err("no es un contenedor APFS (falta NXSB)".into());
    }
    let tam = u32_en(&b0, 36);
    if !(4096..=65536).contains(&tam) || !tam.is_power_of_two() {
        return Err(format!("tamaño de bloque raro: {tam}"));
    }
    let b0 = if tam == 4096 { b0 } else { d.bloque(0, tam).ok_or("no se lee el bloque 0")? };
    let desc_bloques = u32_en(&b0, 104);
    let desc_base = u64_en(&b0, 112);
    if desc_bloques & 0x8000_0000 != 0 {
        return Err("el área de checkpoints no es contigua (no soportado)".into());
    }
    // 2. El superbloque más nuevo del área de descriptores.
    let mut mejor: Option<(u64, Vec<u8>, u64)> = None;
    for i in 0..desc_bloques as u64 {
        let Some(b) = d.bloque(desc_base + i, tam) else { continue };
        if valido(&b) && tipo(&b) == TIPO_NX_SUPERBLOCK && &b[32..36] == NX_MAGIC {
            let xid = u64_en(&b, 16);
            if mejor.as_ref().map(|(x, _, _)| xid > *x).unwrap_or(true) {
                mejor = Some((xid, b, i));
            }
        }
    }
    let (xid, sb, _) = mejor.ok_or("ningún superbloque válido en el área de checkpoints")?;
    let total = u64_en(&sb, 40);
    let spaceman_oid = u64_en(&sb, 152);
    // 3. El checkpoint map del mismo xid: dónde está el space manager.
    let mut paddr = None;
    for i in 0..desc_bloques as u64 {
        let Some(b) = d.bloque(desc_base + i, tam) else { continue };
        if !valido(&b) || tipo(&b) != TIPO_CHECKPOINT_MAP || u64_en(&b, 16) != xid {
            continue;
        }
        let n = u32_en(&b, 36) as usize;
        for k in 0..n {
            let o = 40 + k * 40;
            if o + 40 > b.len() {
                break;
            }
            if u64_en(&b, o + 24) == spaceman_oid {
                paddr = Some(u64_en(&b, o + 32));
            }
        }
    }
    let paddr = paddr.ok_or("el checkpoint map no tiene el space manager")?;
    // 4. El space manager.
    let sm = d.bloque(paddr, tam).ok_or("no se lee el space manager")?;
    if !valido(&sm) || tipo(&sm) != TIPO_SPACEMAN {
        return Err("el space manager no pasa su checksum".into());
    }
    // sm_dev[SD_MAIN] empieza en 48: block_count (8), chunk_count (8), cib (4), cab (4), free_count (8).
    let sm_bloques = u64_en(&sm, 48);
    let libres = u64_en(&sm, 72);
    if libres > sm_bloques || sm_bloques > total {
        return Err(format!("cuentas imposibles: libres {libres} de {sm_bloques} (contenedor {total})"));
    }
    Ok(Espacio { uuid: uuid(&sb[72..88]), bloque: tam, total: total * tam as u64, libre: libres * tam as u64, xid })
}

fn json(e: &Espacio) -> String {
    format!("{{\"version\": 1, \"uuid\": \"{}\", \"total\": {}, \"libre\": {}, \"tamano_bloque\": {}, \"xid\": {}}}\n", e.uuid, e.total, e.libre, e.bloque, e.xid)
}

fn main() {
    let mut args = std::env::args().skip(1);
    let Some(dev) = args.next() else {
        eprintln!("uso: mint-macos-apfs-espacio DISPOSITIVO [--guardar]");
        exit(2)
    };
    let guardar = args.next().as_deref() == Some("--guardar");
    let e = File::open(&dev).map_err(|e| format!("{dev}: {e}")).and_then(|mut f| leer(&mut f));
    let e = match e {
        Ok(e) => e,
        Err(m) => {
            eprintln!("mint-macos-apfs-espacio: {dev}: {m}");
            exit(1)
        }
    };
    let t = json(&e);
    print!("{t}");
    if guardar {
        let dir = Path::new("/run/mint-macos/apfs");
        let r = fs::create_dir_all(dir).and_then(|_| {
            let tmp = dir.join(format!(".{}.tmp", e.uuid));
            fs::write(&tmp, &t)?;
            fs::set_permissions(&tmp, fs::Permissions::from_mode(0o644))?;
            fs::rename(&tmp, dir.join(format!("{}.json", e.uuid)))
        });
        if let Err(m) = r {
            eprintln!("mint-macos-apfs-espacio: {}: {m}", dir.display());
            exit(1);
        }
    }
}

#[cfg(test)]
mod pruebas {
    use super::*;
    use std::collections::HashMap;

    /// Una imagen de juguete en memoria: bloques sueltos por número.
    struct Imagen(HashMap<u64, Vec<u8>>, u32);
    impl Disco for Imagen {
        fn bloque(&mut self, n: u64, tam: u32) -> Option<Vec<u8>> {
            let mut b = self.0.get(&n).cloned().unwrap_or_else(|| vec![0; self.1 as usize]);
            b.resize(tam as usize, 0);
            Some(b)
        }
    }

    fn objeto(tam: u32, oid: u64, xid: u64, tipo: u32) -> Vec<u8> {
        let mut b = vec![0u8; tam as usize];
        b[8..16].copy_from_slice(&oid.to_le_bytes());
        b[16..24].copy_from_slice(&xid.to_le_bytes());
        b[24..28].copy_from_slice(&(tipo | 0x8000_0000).to_le_bytes());
        b
    }
    fn sellar(mut b: Vec<u8>) -> Vec<u8> {
        let c = fletcher64(&b);
        b[0..8].copy_from_slice(&c.to_le_bytes());
        b
    }
    fn superbloque(tam: u32, xid: u64, total: u64) -> Vec<u8> {
        let mut b = objeto(tam, 1, xid, TIPO_NX_SUPERBLOCK);
        b[32..36].copy_from_slice(NX_MAGIC);
        b[36..40].copy_from_slice(&tam.to_le_bytes());
        b[40..48].copy_from_slice(&total.to_le_bytes());
        b[72..88].copy_from_slice(&[0x3c, 0x3d, 0xa2, 0xad, 0xc4, 0xc8, 0x42, 0x75, 0x99, 0x71, 0x70, 0xb3, 0xf2, 0x61, 0x6f, 0x13]);
        b[104..108].copy_from_slice(&8u32.to_le_bytes()); // 8 bloques de descriptores
        b[112..120].copy_from_slice(&1u64.to_le_bytes()); // desde el bloque 1
        b[152..160].copy_from_slice(&0x400u64.to_le_bytes()); // spaceman oid
        sellar(b)
    }

    fn imagen() -> Imagen {
        let tam = 4096;
        let mut m = HashMap::new();
        m.insert(0, superbloque(tam, 5, 1000)); // el del bloque 0, viejo
        m.insert(1, superbloque(tam, 5, 1000));
        m.insert(3, superbloque(tam, 9, 1000)); // el más nuevo
        // Checkpoint maps: uno viejo (xid 5) que apunta a otro sitio y el bueno (xid 9).
        for (bloque, xid, paddr) in [(2u64, 5u64, 50u64), (4, 9, 60)] {
            let mut c = objeto(tam, bloque, xid, TIPO_CHECKPOINT_MAP);
            c[36..40].copy_from_slice(&1u32.to_le_bytes());
            c[40 + 24..40 + 32].copy_from_slice(&0x400u64.to_le_bytes());
            c[40 + 32..40 + 40].copy_from_slice(&paddr.to_le_bytes());
            m.insert(bloque, sellar(c));
        }
        for (bloque, libres) in [(50u64, 900u64), (60, 250)] {
            let mut s = objeto(tam, 0x400, 9, TIPO_SPACEMAN);
            s[48..56].copy_from_slice(&1000u64.to_le_bytes());
            s[72..80].copy_from_slice(&libres.to_le_bytes());
            m.insert(bloque, sellar(s));
        }
        Imagen(m, tam)
    }

    #[test]
    fn el_checkpoint_mas_nuevo_manda() {
        let e = leer(&mut imagen()).unwrap();
        assert_eq!(e, Espacio { uuid: "3c3da2ad-c4c8-4275-9971-70b3f2616f13".into(), bloque: 4096, total: 1000 * 4096, libre: 250 * 4096, xid: 9 });
    }

    #[test]
    fn checksum_malo_no_cuenta() {
        let mut i = imagen();
        i.0.get_mut(&3).unwrap()[200] ^= 1; // el superbloque nuevo, roto
        assert_eq!(leer(&mut i).unwrap().xid, 5, "se queda con el anterior bueno");
        i.0.get_mut(&50).unwrap()[100] ^= 1; // y el space manager de ese, roto
        assert!(leer(&mut i).is_err());
    }

    #[test]
    fn no_es_apfs() {
        let mut i = Imagen(HashMap::new(), 4096);
        assert!(leer(&mut i).unwrap_err().contains("NXSB"));
    }

    /// Contra los discos de verdad si se pueden leer (grupo disk): el total tiene que ser
    /// el de la partición, y lo libre, menos que eso.
    #[test]
    fn discos_de_verdad() {
        for u in ["ad6302c4-5b01-4d3f-b5f7-bcf7490190b3", "3c3da2ad-c4c8-4275-9971-70b3f2616f13"] {
            let p = format!("/dev/disk/by-uuid/{u}");
            let Ok(mut f) = File::open(&p) else { continue };
            let e = leer(&mut f).unwrap();
            assert_eq!(e.uuid, u);
            let part = std::process::Command::new("lsblk").args(["-bndo", "SIZE", &p]).output().unwrap();
            let part: u64 = String::from_utf8_lossy(&part.stdout).trim().parse().unwrap();
            assert!(e.total <= part && e.total >= part - part / 100, "{} vs {part}", e.total);
            assert!(e.libre < e.total);
            eprintln!("{u}: libre {:.2} GB de {:.2} GB", e.libre as f64 / 1e9, e.total as f64 / 1e9);
        }
    }
}
