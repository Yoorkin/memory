/// Represent memory 内存
pub(readonly) struct Memory {
  offset : Int
  length : Int
}

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
}

priv struct LinearMemory {
  mut start : Chunk
  mut end : Chunk
}

let memory : LinearMemory = {
  let length = memory_size_ffi()
  let chunk = {
    memory: { offset: 0, length },
    occupied: false,
    prev: None,
    next: None,
  }
  { start: chunk, end: chunk }
}

fn grow(self : LinearMemory, size : Int) -> Bool {
  let delta = size.lsr(16) + 1
  let old_size = memory_size_ffi()
  let new_size = memory_grow_ffi(delta)
  if new_size >= old_size + delta {
    if self.end.occupied {
      let chunk : Chunk = {
        memory: {
          offset: old_size.lsl(16),
          length: (new_size - old_size).lsl(16),
        },
        occupied: false,
        prev: Some(self.end),
        next: None,
      }
      self.end.next = Some(chunk)
      self.end = chunk
    } else {
      self.end.memory = {..self.end.memory,
        length: self.end.memory.length + (new_size - old_size).lsl(16),
      }
    }
  }
  new_size >= old_size + delta
}

/// Allocate memory 分配内存
pub fn allocate(size : Int) -> Option[Memory] {
  let mut ptr : Option[Chunk] = Some(memory.start)
  let mut has_next = true
  while has_next {
    match ptr {
      None => {
        has_next = false
      }
      Some(chunk) => if chunk.memory.length < size {
        ptr = chunk.next
      } else if chunk.memory.length == size {
        chunk.occupied = true
        return Some(chunk.memory)
      } else {
        let new_chunk : Chunk = {
          memory: {
            offset: chunk.memory.offset + size,
            length: chunk.memory.length - size,
          },
          occupied: false,
          prev: Some(chunk),
          next: chunk.next,
        }
        chunk.memory = {..chunk.memory, length: size }
        chunk.occupied = true
        chunk.next = Some(new_chunk)
        match new_chunk.next {
          None => ()
          Some(c) => {
            c.prev = Some(new_chunk)
          }
        }
        return Some(chunk.memory)
      }
    }
  }
  if memory.grow(size) {
    allocate(size)
  } else {
    None
  }
}

/// Free Memory 释放内存
pub fn free(self : Memory) -> Option[Unit] {
  let mut ptr : Option[Chunk] = Some(memory.start)
  let mut has_next = true
  while has_next {
    match ptr {
      None => {
        has_next = false
      }
      Some(chunk) => if chunk.memory.length == self.length && chunk.memory.offset ==
      self.offset {
        chunk.occupied = false
        match (chunk.prev, chunk.next) {
          (
            Some({ occupied: false, .. } as prev),
            Some({ occupied: false, .. } as next),
          ) => {
            prev.memory = {..prev.memory,
              length: prev.memory.length + chunk.memory.length + next.memory.length,
            }
            prev.next = next.next
            match next.next {
              Some(next_next) => {
                next_next.prev = Some(prev)
              }
              None => {
                memory.end = prev
              }
            }
          }
          (Some({ occupied: false, .. } as prev), None) => {
            prev.memory = {..prev.memory,
              length: prev.memory.length + chunk.memory.length,
            }
            prev.next = None
            memory.end = prev
          }
          (None, Some({ occupied: false, .. } as next)) => {
            chunk.memory = {..chunk.memory,
              length: chunk.memory.length + next.memory.length,
            }
            chunk.next = next.next
            match next.next {
              Some(next_next) => {
                next_next.prev = Some(chunk)
              }
              None => {
                memory.end = chunk
              }
            }
          }
          _ => ()
        }
        return Some(())
      } else {
        ptr = chunk.next
      }
    }
  }
  None
}

/// Reallocate Memory 重新分配内存
pub fn reallocate(self : Memory, _alignment : Int, new_length : Int) ->
     Option[Memory] {
  // TODO: write a better one
  let new_memory = allocate(new_length)?
  let length = if self.length < new_length {
    self.length
  } else {
    new_length
  }
  memory_copy_ffi(self.offset, new_memory.offset, length)
  Some(new_memory)
}
