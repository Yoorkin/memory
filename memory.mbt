/// Represent memory 内存
pub(readonly) struct Memory {
  offset : Int
  length : Int
} derive(Debug)

/// Load Byte 读取字节
pub fn load8(self : Memory, offset : Int) -> Option[Int] {
  if offset < 0 || offset + 1 > self.length {
    None
  } else {
    Some(load8_ffi(self.offset + offset))
  }
}

/// Load Int32 读取32位整数
pub fn load32(self : Memory, offset : Int) -> Option[Int] {
  if offset < 0 || offset + 4 > self.length {
    None
  } else {
    Some(load32_ffi(self.offset + offset))
  }
}

/// Load Int64 读取64位整数
pub fn load64(self : Memory, offset : Int) -> Option[Int64] {
  if offset < 0 || offset + 8 > self.length {
    None
  } else {
    Some(load64_ffi(self.offset + offset))
  }
}

/// Store Byte 存储字节
pub fn store8(self : Memory, offset : Int, value : Int) -> Option[Unit] {
  if offset < 0 || offset + 1 > self.length {
    None
  } else {
    Some(store8_ffi(self.offset + offset, value))
  }
}

/// Store Int32 存储32位整数
pub fn store32(self : Memory, offset : Int, value : Int) -> Option[Unit] {
  if offset < 0 || offset + 4 > self.length {
    None
  } else {
    Some(store32_ffi(self.offset + offset, value))
  }
}

/// Store Int64 存储64位整数
pub fn store64(self : Memory, offset : Int, value : Int64) -> Option[Unit] {
  if offset < 0 || offset + 1 > self.length {
    None
  } else {
    Some(store64_ffi(self.offset + offset, value))
  }
}

/// Load Bytes 读取数据块
pub fn load_bytes(self : Memory) -> Bytes {
  let bytes = Bytes::make(self.length, 0)
  let mut i = 0
  while i < self.length, i = i + 1 {
    bytes[i] = load8_ffi(self.offset + i)
  }
  bytes
}

/// Store Bytes 存储数据块
pub fn store_bytes(self : Memory, bytes : Bytes) -> Unit {
  let len = if self.length < bytes.length() {
    self.length
  } else {
    bytes.length()
  }
  let mut i = 0
  while i < len, i = i + 1 {
    store8_ffi(self.offset + i, bytes[i])
  }
}

fn load8_ffi(pos : Int) -> Int = "(func $load8 (param $pos i32) (result i32) (i32.load8_u (local.get $pos)))"

fn load32_ffi(pos : Int) -> Int = "(func $load32 (param $pos i32) (result i32) (i32.load (local.get $pos)))"

fn load64_ffi(pos : Int) -> Int64 = "(func $load64 (param $pos i32) (result i64) (i64.load (local.get $pos)))"

fn store8_ffi(pos : Int, value : Int) = "(func $store8 (param $pos i32) (param $value i32) (i32.store8 (local.get $pos) (local.get $value)))"

fn store32_ffi(pos : Int, value : Int) = "(func $store32 (param $pos i32) (param $value i32) (i32.store (local.get $pos) (local.get $value)))"

fn store64_ffi(pos : Int, value : Int64) = "(func $store64 (param $pos i32) (param $value i64) (i64.store (local.get $pos) (local.get $value)))"

fn memory_size_ffi() -> Int = "(func $memory_size (result i32) (memory.size))"

fn memory_grow_ffi(delta : Int) -> Int = "(func $memory_grow (param $size i32) (result i32) (memory.grow (local.get $size)))"

fn memory_copy_ffi(origin : Int, target : Int, len : Int) = "(func $memory_copy (param $origin i32) (param $target i32) (param $len i32) (memory.copy (local.get $origin) (local.get $target) (local.get $len)))"

priv struct Chunk {
  mut memory : Memory
  mut occupied : Bool
  mut prev : Option[Chunk]
  mut next : Option[Chunk]
} derive(Debug)

priv struct LinearMemory {
  mut start : Chunk
  mut end : Chunk
}

fn debug_write(self : LinearMemory, buffer : Buffer) {
  self.to_array().debug_write(buffer)
}

fn to_array(self : LinearMemory) -> Array[(Memory, Bool)] {
  let mut length = 0
  let mut ptr : Option[Chunk] = Some(self.start)
  let mut has_next = true
  while has_next {
    match ptr {
      None => {
        has_next = false
      }
      Some(chunk) => {
        length = length + 1
        ptr = chunk.next
      }
    }
  }
  let array = Array::make(length, ({ offset: 0, length: 0 }, true))
  let mut length = 0
  let mut ptr : Option[Chunk] = Some(self.start)
  let mut has_next = true
  while has_next {
    match ptr {
      None => {
        has_next = false
      }
      Some(chunk) => {
        array[length] = (chunk.memory, chunk.occupied)
        length = length + 1
        ptr = chunk.next
      }
    }
  }
  array
}

let memory : LinearMemory = {
  let length = memory_size_ffi().lsl(16)
  let chunk = {
    memory: { offset: 0, length },
    occupied: false,
    prev: None,
    next: None,
  }
  { start: chunk, end: chunk }
}

/// Create memory 创建内存
/// Only valid if it is actually an allocated memory that is in use
/// 当该内存确实为被分配的内存时输入合法
pub fn Memory::make(offset : Int, length : Int) -> Option[Memory] {
  let chunk = { offset, length }.locate_chunk()?
  Some(chunk.memory)
}

fn Memory::locate_chunk(m : Memory) -> Option[Chunk] {
  let mut ptr : Option[Chunk] = Some(memory.start)
  let mut has_next = true
  while has_next {
    match ptr {
      None => {
        has_next = false
      }
      Some(chunk) => if chunk.memory.length == m.length && chunk.memory.offset ==
      m.offset {
        return Some(chunk)
      } else if chunk.memory.offset < m.offset {
        ptr = chunk.next
      } else {
        has_next = false
      }
    }
  }
  None
}

fn grow(self : LinearMemory, size : Int) -> Bool {
  let delta = size.lsr(16) + 1
  let old_size = memory_size_ffi()
  let errno = memory_grow_ffi(delta)
  if errno != -1 {
    if self.end.occupied {
      let chunk : Chunk = {
        memory: { offset: old_size.lsl(16), length: delta.lsl(16) },
        occupied: false,
        prev: Some(self.end),
        next: None,
      }
      self.end.next = Some(chunk)
      self.end = chunk
    } else {
      self.end.memory = {..self.end.memory,
        length: self.end.memory.length + delta.lsl(16),
      }
    }
    true
  } else {
    false
  }
}

/// Allocate memory 分配内存
pub fn allocate(size : Int) -> Option[Memory] {
  if size <= 0 {
    return None
  }
  let mut ptr : Option[Chunk] = Some(memory.start)
  let mut has_next = true
  while has_next {
    match ptr {
      None => {
        has_next = false
      }
      Some({ occupied: false, .. } as chunk) => if chunk.memory.length < size {
        ptr = chunk.next
      } else {
        if chunk.memory.length > size {
          let _ = chunk.split(size)?

        }
        chunk.occupied = true
        return Some(chunk.memory)
      }
      Some(chunk) => {
        ptr = chunk.next
      }
    }
  }
  if memory.grow(size) {
    allocate(size)
  } else {
    None
  }
}

/// return merged or self
fn Chunk::merge_next(chunk : Chunk, next : Chunk) -> Chunk {
  chunk.memory = {..chunk.memory,
    length: chunk.memory.length + next.memory.length,
  }
  match next.next {
    Some(next_next) => {
      chunk.next = Some(next_next)
      next_next.prev = Some(chunk)
    }
    None => {
      chunk.next = None
      memory.end = chunk
    }
  }
  chunk
}

/// return next
fn Chunk::split(chunk : Chunk, length : Int) -> Option[Chunk] {
  if length < chunk.memory.length {
    let new_chunk : Chunk = {
      memory: {
        offset: chunk.memory.offset + length,
        length: chunk.memory.length - length,
      },
      occupied: false,
      prev: Some(chunk),
      next: chunk.next,
    }
    chunk.memory = {..chunk.memory, length, }
    chunk.next = Some(new_chunk)
    match new_chunk.next {
      None => {
        memory.end = new_chunk
      }
      Some(next_next) => {
        next_next.prev = Some(new_chunk)
      }
    }
    Some(new_chunk)
  } else {
    None
  }
}

fn Chunk::free(chunk : Chunk) {
  chunk.occupied = false
  let chunk = match chunk.prev {
    Some({ occupied: false, .. } as prev) => prev.merge_next(chunk)
    _ => chunk
  }
  match chunk.next {
    Some({ occupied: false, .. } as next) => {
      let _ = chunk.merge_next(next)

    }
    _ => ()
  }
}

/// Free Memory 释放内存
pub fn free(self : Memory) -> Option[Unit] {
  let chunk = self.locate_chunk()?
  if chunk.occupied {
    Some(chunk.free())
  } else {
    None
  }
}

/// Reallocate Memory 重新分配内存
pub fn reallocate(self : Memory, _alignment : Int, new_length : Int) ->
     Option[Memory] {
  if self.length <= 0 {
    allocate(new_length)
  } else if new_length <= 0 {
    self.free()
    None
  } else if new_length < self.length {
    let chunk = self.locate_chunk()?
    if chunk.occupied {
      match chunk.next {
        Some({ occupied: false, .. } as next) => {
          chunk.merge_next(next)
          let _ = chunk.split(new_length)
          Some(chunk.memory)
        }
        _ => {
          let _ = chunk.split(new_length)
          Some(chunk.memory)
        }
      }
    } else {
      None
    }
  } else {
    let chunk = self.locate_chunk()?
    if chunk.occupied {
      chunk.occupied = false
      let chunk = match chunk.prev {
        Some({ occupied: false, .. } as prev) => prev.merge_next(chunk)
        _ => chunk
      }
      match chunk.next {
        Some({ occupied: false, .. } as next) => {
          let _ = chunk.merge_next(next)

        }
        _ => ()
      }
      if chunk.memory.length < new_length {
        let new_memory = allocate(new_length).unwrap()
        memory_copy_ffi(self.offset, new_memory.offset, self.length)
        Some(new_memory)
      } else {
        chunk.occupied = true
        chunk.split(new_length)
        memory_copy_ffi(self.offset, chunk.memory.offset, self.length)
        Some(chunk.memory)
      }
    } else {
      None
    }
  }
}
