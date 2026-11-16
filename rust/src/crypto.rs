/// Pure Rust implementation of MD5 (RFC 1321), RC4, and Standard PDF Security Handler
/// (ISO 32000-1 / PDF 1.7 Standard Security Handler, Revision 2).

pub fn md5(data: &[u8]) -> [u8; 16] {
    let mut state: [u32; 4] = [0x67452301, 0xefcdab89, 0x98badcfe, 0x10325476];

    let bit_len = (data.len() as u64) * 8;
    let mut msg = data.to_vec();
    msg.push(0x80);
    while (msg.len() % 64) != 56 {
        msg.push(0x00);
    }
    msg.extend_from_slice(&bit_len.to_le_bytes());

    for chunk in msg.chunks_exact(64) {
        let mut m = [0u32; 16];
        for (i, c) in chunk.chunks_exact(4).enumerate() {
            m[i] = u32::from_le_bytes([c[0], c[1], c[2], c[3]]);
        }

        let mut a = state[0];
        let mut b = state[1];
        let mut c = state[2];
        let mut d = state[3];

        const S: [u32; 64] = [
            7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22, 7, 12, 17, 22,
            5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20, 5, 9, 14, 20,
            4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23, 4, 11, 16, 23,
            6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21, 6, 10, 15, 21,
        ];

        const K: [u32; 64] = [
            0xd76aa478, 0xe8c7b756, 0x242070db, 0xc1bdceee,
            0xf57c0faf, 0x4787c62a, 0xa8304613, 0xfd469501,
            0x698098d8, 0x8b44f7af, 0xffff5bb1, 0x895cd7be,
            0x6b901122, 0xfd987193, 0xa679438e, 0x49b40821,
            0xf61e2562, 0xc040b340, 0x265e5a51, 0xe9b6c7aa,
            0xd62f105d, 0x02441453, 0xd8a1e681, 0xe7d3fbc8,
            0x21e1cde6, 0xc33707d6, 0xf4d50d87, 0x455a14ed,
            0xa9e3e905, 0xfcefa3f8, 0x676f02d9, 0x8d2a4c8a,
            0xfffa3942, 0x8771f681, 0x6d9d6122, 0xfde5380c,
            0xa4beea44, 0x4bdecfa9, 0xf6bb4b60, 0xbebfbc70,
            0x289b7ec6, 0xeaa127fa, 0xd4ef3085, 0x04881d05,
            0xd9d4d039, 0xe6db99e5, 0x1fa27cf8, 0xc4ac5665,
            0xf4292244, 0x432aff97, 0xab9423a7, 0xfc93a039,
            0x655b59c3, 0x8f0ccc92, 0xffeff47d, 0x85845dd1,
            0x6fa87e4f, 0xfe2ce6e0, 0xa3014314, 0x4e0811a1,
            0xf7537e82, 0xbd3af235, 0x2ad7d2bb, 0xeb86d391,
        ];

        for i in 0..64 {
            let (f, g) = match i {
                0..=15 => ((b & c) | (!b & d), i),
                16..=31 => ((d & b) | (!d & c), (5 * i + 1) % 16),
                32..=47 => (b ^ c ^ d, (3 * i + 5) % 16),
                _ => (c ^ (b | !d), (7 * i) % 16),
            };

            let temp = d;
            d = c;
            c = b;
            let sum = a.wrapping_add(f).wrapping_add(K[i]).wrapping_add(m[g]);
            b = b.wrapping_add(sum.rotate_left(S[i]));
            a = temp;
        }

        state[0] = state[0].wrapping_add(a);
        state[1] = state[1].wrapping_add(b);
        state[2] = state[2].wrapping_add(c);
        state[3] = state[3].wrapping_add(d);
    }

    let mut out = [0u8; 16];
    out[0..4].copy_from_slice(&state[0].to_le_bytes());
    out[4..8].copy_from_slice(&state[1].to_le_bytes());
    out[8..12].copy_from_slice(&state[2].to_le_bytes());
    out[12..16].copy_from_slice(&state[3].to_le_bytes());
    out
}

pub fn rc4(key: &[u8], data: &[u8]) -> Vec<u8> {
    let mut s = [0u8; 256];
    for (i, v) in s.iter_mut().enumerate() {
        *v = i as u8;
    }

    let mut j: usize = 0;
    for i in 0..256 {
        j = (j + s[i] as usize + key[i % key.len()] as usize) % 256;
        s.swap(i, j);
    }

    let mut i = 0usize;
    let mut j = 0usize;
    let mut out = Vec::with_capacity(data.len());

    for &byte in data {
        i = (i + 1) % 256;
        j = (j + s[i] as usize) % 256;
        s.swap(i, j);
        let k = s[(s[i] as usize + s[j] as usize) % 256];
        out.push(byte ^ k);
    }

    out
}

pub const PDF_PADDING: [u8; 32] = [
    0x28, 0xBF, 0x4E, 0x5E, 0x4E, 0x75, 0x8A, 0x41,
    0x64, 0x00, 0x4E, 0x56, 0xFF, 0xFA, 0x01, 0x08,
    0x2E, 0x2E, 0x00, 0xB6, 0xD0, 0x68, 0x3E, 0x80,
    0x2F, 0x0C, 0xA9, 0xFE, 0x64, 0x53, 0x69, 0x7A,
];

pub struct PdfSecurity {
    pub file_key: [u8; 5],
    pub o_val: [u8; 32],
    pub u_val: [u8; 32],
    pub p_val: i32,
}

impl PdfSecurity {
    pub fn new(password: &str, file_id: &[u8; 16]) -> Self {
        let p_val: i32 = -64; // Print & copy allowed, password required to open

        // 1. Pad password to 32 bytes
        let mut padded = [0u8; 32];
        let pw_bytes = password.as_bytes();
        let copy_len = pw_bytes.len().min(32);
        padded[..copy_len].copy_from_slice(&pw_bytes[..copy_len]);
        padded[copy_len..].copy_from_slice(&PDF_PADDING[..(32 - copy_len)]);

        // 2. Compute O value (Algorithm 3.3)
        let o_key = md5(&padded);
        let o_val_vec = rc4(&o_key[..5], &padded);
        let mut o_val = [0u8; 32];
        o_val.copy_from_slice(&o_val_vec[..32]);

        // 3. Compute encryption key (Algorithm 3.2)
        let mut key_input = Vec::new();
        key_input.extend_from_slice(&padded);
        key_input.extend_from_slice(&o_val);
        key_input.extend_from_slice(&p_val.to_le_bytes());
        key_input.extend_from_slice(file_id);

        let hash = md5(&key_input);
        let mut file_key = [0u8; 5];
        file_key.copy_from_slice(&hash[..5]);

        // 4. Compute U value (Algorithm 3.4)
        let u_val_vec = rc4(&file_key, &PDF_PADDING);
        let mut u_val = [0u8; 32];
        u_val.copy_from_slice(&u_val_vec[..32]);

        Self {
            file_key,
            o_val,
            u_val,
            p_val,
        }
    }

    /// Encrypt an object's stream data using object id and generation
    pub fn encrypt_stream(&self, obj_id: u32, gen_id: u16, data: &[u8]) -> Vec<u8> {
        let mut obj_key_input = Vec::with_capacity(10);
        obj_key_input.extend_from_slice(&self.file_key);
        obj_key_input.push((obj_id & 0xFF) as u8);
        obj_key_input.push(((obj_id >> 8) & 0xFF) as u8);
        obj_key_input.push(((obj_id >> 16) & 0xFF) as u8);
        obj_key_input.push((gen_id & 0xFF) as u8);
        obj_key_input.push(((gen_id >> 8) & 0xFF) as u8);

        let hash = md5(&obj_key_input);
        let key_len = 10.min(hash.len());
        rc4(&hash[..key_len], data)
    }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn test_md5() {
        assert_eq!(
            hex_encode(&md5(b"")),
            "d41d8cd98f00b204e9800998ecf8427e"
        );
        assert_eq!(
            hex_encode(&md5(b"The quick brown fox jumps over the lazy dog")),
            "9e107d9d372bb6826bd81d3542a419d6"
        );
    }

    #[test]
    fn test_rc4_roundtrip() {
        let key = b"arch_scan_secret_key";
        let data = b"Confidential scanned document content";
        let encrypted = rc4(key, data);
        assert_ne!(data, encrypted.as_slice());
        let decrypted = rc4(key, &encrypted);
        assert_eq!(data, decrypted.as_slice());
    }

    #[test]
    fn test_pdf_security_key_generation() {
        let file_id = [0x5au8; 16];
        let sec = PdfSecurity::new("my_pass", &file_id);
        assert_ne!(sec.file_key, [0u8; 5]);
        assert_ne!(sec.u_val, [0u8; 32]);
    }

    fn hex_encode(bytes: &[u8]) -> String {
        bytes.iter().map(|b| format!("{:02x}", b)).collect()
    }
}
