# Multi-threaded Database Server

A high-performance Redis-like key-value database server implemented in C++, featuring advanced data structures, non-blocking I/O, and concurrent processing.

## Overview

This project implements a production-grade database server with support for:
- String key-value storage
- Sorted sets (ZSets) with dual indexing
- Time-to-live (TTL) expiration management
- Connection pooling with idle timeout
- Non-blocking I/O using `poll()`
- Thread pool for asynchronous cleanup operations
- Progressive hash table rehashing for smooth resizing

**Port:** 1234

## Architecture

### System Design

The server operates using an event-driven, single-threaded request handler with non-blocking I/O multiplexing, augmented by a thread pool for CPU-intensive background operations.

```
Client Connections
       ↓
Event Loop (poll)
       ↓
Request Handlers (do_get, do_set, do_zadd, etc.)
       ↓
Data Structures
├─ Hash Table (main key-value store)
├─ AVL Tree (sorted set indexing)
├─ Min-Heap (TTL tracking)
├─ Circular Linked List (idle connection timeout)
└─ Thread Pool (async cleanup)
```

### Global State (`g_data`)

- **`HMap db`**: Main hash table storing all key-value pairs
- **`std::vector<Conn *> fd2conn`**: Maps file descriptors to connection structures
- **`DList idle_list`**: Doubly-linked circular list tracking idle connections
- **`std::vector<HeapItem> heap`**: Min-heap for TTL expiration tracking
- **`TheadPool thread_pool`**: Worker thread pool (4 threads by default)

## Data Structures

### 1. Hash Table (`hashtable.h/cpp`)

**Purpose:** Store key-value pairs with O(1) average lookup/insert/delete

**Features:**
- Progressive rehashing using two concurrent hash tables (newer/older)
- Migrates items incrementally (128 per operation) to avoid blocking
- Load factor threshold of 8x triggers rehashing
- Intrusive design (nodes embedded in payload)
- O(1) amortized operations

**Key Functions:**
- `hm_lookup()`: Find entry by key
- `hm_insert()`: Add or update entry
- `hm_delete()`: Remove entry
- `hm_foreach()`: Iterate all entries
- `hm_clear()`: Deallocate all memory

### 2. AVL Tree (`avl.h/cpp`)

**Purpose:** Self-balancing binary search tree for range queries and ordered access

**Features:**
- Height and subtree count tracking for O(log N) offset operations
- Automatic rebalancing via rotations
- Parent pointers for upward traversal
- Maintains height difference ≤ 1 between subtrees

**Key Functions:**
- `avl_fix()`: Rebalance after insertions/deletions
- `avl_del()`: Remove node with automatic rebalancing
- `avl_offset()`: Navigate to node at given offset in O(log N)

**Operations:** O(log N) insert, delete, search, and offset navigation

### 3. Sorted Set (`zset.h/cpp`)

**Purpose:** Store weighted elements with fast lookups and range queries

**Dual Indexing:**
- **AVL Tree**: Indexed by (score, name) tuple for ordered access and range queries
- **Hash Table**: Indexed by name for O(1) element lookups

**Key Functions:**
- `zset_insert()`: Add/update element with score
- `zset_lookup()`: Find element by name
- `zset_delete()`: Remove element
- `zset_seekge()`: Find first element ≥ score
- `znode_offset()`: Navigate to next/previous element
- `zset_clear()`: Deallocate all elements

**Time Complexity:**
- Insert/update: O(log N)
- Lookup by name: O(1)
- Range query: O(log N + K) where K = result size
- Delete: O(log N)

### 4. Min-Heap (`heap.h/cpp`)

**Purpose:** Track TTL expiration times efficiently

**Features:**
- O(log N) insertion and deletion
- O(1) minimum element access
- Smart updates: bubbles up if value decreases, down if increases
- Stores references to Entry heap_idx for O(1) updates

**Key Functions:**
- `heap_update()`: Update element's expiration time
- `heap_up()`: Bubble element up the heap
- `heap_down()`: Bubble element down the heap

### 5. Circular Doubly-Linked List (`list.h`)

**Purpose:** Track idle connections for timeout management

**Features:**
- Intrusive design (embedded in Conn struct)
- O(1) insertion and removal
- Circular structure (last→first)
- FIFO ordering for LRU-style timeout detection

**Key Functions:**
- `dlist_init()`: Initialize as circular sentinel
- `dlist_insert_before()`: Insert node before target
- `dlist_detach()`: Remove node from list
- `dlist_empty()`: Check if empty (only sentinel remains)

### 6. Thread Pool (`thread_pool.h/cpp`)

**Purpose:** Async cleanup of large data structures

**Features:**
- Fixed number of worker threads (4 by default)
- Mutex-protected work queue
- Condition variable for signaling
- Indefinite worker loop

**Key Functions:**
- `thread_pool_init()`: Create worker threads
- `thread_pool_queue()`: Enqueue work item

**Use Cases:**
- Async deletion of large sorted sets (>1000 items)
- Prevents server stalls during heavy cleanup

## Protocol

### Message Format

**Request:**
```
[u32: num_strings]
[u32: len1][bytes: str1]
[u32: len2][bytes: str2]
...
[u32: lenN][bytes: strN]
```

**Response:**
```
[u32: message_length]
[u8: tag][type-specific data...]
```

### Response Tags

- `TAG_NIL (0)`: Null value
- `TAG_ERR (1)`: Error with code and message
- `TAG_STR (2)`: String with length prefix
- `TAG_INT (3)`: 64-bit signed integer
- `TAG_DBL (4)`: IEEE 754 double
- `TAG_ARR (5)`: Array with element count

### Error Codes

- `ERR_UNKNOWN (1)`: Unknown command
- `ERR_TOO_BIG (2)`: Response exceeds 32MB limit
- `ERR_BAD_TYP (3)`: Type mismatch (e.g., string operation on zset)
- `ERR_BAD_ARG (4)`: Invalid arguments

## Supported Commands

### String Operations

**`get key`**
- Returns string value or nil
- Time: O(1)

**`set key value`**
- Store string, overwrite if exists
- Time: O(1) amortized

**`del key`**
- Remove key, deallocate value
- Returns 1 if removed, 0 if not found
- Time: O(1) amortized

### TTL Operations

**`pexpire key ttl_ms`**
- Set time-to-live in milliseconds
- Negative TTL removes expiration
- Time: O(log N) where N = number of keys with TTL

**`pttl key`**
- Get remaining TTL in milliseconds
- Returns -2 if key not found, -1 if no TTL
- Time: O(1)

### Sorted Set Operations

**`zadd zset score name`**
- Add element with score, or update score if exists
- Returns 1 if added, 0 if updated
- Time: O(log N)

**`zrem zset name`**
- Remove element from sorted set
- Returns 1 if removed, 0 if not found
- Time: O(log N)

**`zscore zset name`**
- Get element's score
- Returns nil if not found
- Time: O(1)

**`zquery zset score name offset limit`**
- Range query: find elements ≥ (score, name)
- Returns array of [name, score, ...] pairs
- Parameters: offset (skip first N matches), limit (max results/2)
- Time: O(log N + K) where K = number of results

### Utility

**`keys`**
- List all keys in the database
- Returns array of all key strings
- Time: O(N)

## Connection Management

### Idle Timeout

- Default: 5000ms (5 seconds)
- Connections moved to end of idle list on activity
- Expired connections detected and destroyed during timer processing

### Connection Structure (`Conn`)

```cpp
struct Conn {
    int fd;                      // socket file descriptor
    bool want_read;              // application's read intent
    bool want_write;             // application's write intent
    bool want_close;             // application's close intent
    Buffer incoming;             // received but unparsed data
    Buffer outgoing;             // serialized responses
    uint64_t last_active_ms;     // last activity timestamp
    DList idle_node;             // node in global idle list
};
```

## Data Expiration

### TTL Management

Keys with TTL are tracked in a min-heap:
1. When TTL is set, heap item is created/updated
2. Entry stores reference to heap position for O(1) updates
3. Expired keys processed in batches (up to 2000 per cycle)
4. Large ZSets (>1000 items) deleted asynchronously via thread pool

### Processing

- Checked once per event loop iteration
- Non-blocking: processes maximum 2000 expirations per cycle
- Prevents server stall during mass expiration events

## Event Loop

### Poll-Based Multiplexing

1. **Prepare poll arguments:**
   - Listening socket with POLLIN
   - All client sockets with events based on state

2. **Calculate timeout:**
   - Next idle timeout
   - Next TTL expiration
   - Return minimum (or -1 for infinite wait)

3. **Wait for readiness:**
   - `poll()` blocks until socket ready or timeout
   - Handles EINTR by restarting

4. **Process readiness:**
   - Listening socket: accept new connections
   - Client sockets: read/write data or handle errors

5. **Timer processing:**
   - Remove idle connections
   - Expire TTL'd keys

### Request Handling Pipeline

```
Socket readable
    ↓
Read data into buffer
    ↓
Parse protocol (extract command)
    ↓
Execute command handler
    ↓
Serialize response
    ↓
Queue in outgoing buffer
    ↓
Socket writable
    ↓
Write to socket
```

## Configuration Constants

| Constant | Value | Purpose |
|----------|-------|---------|
| `k_max_msg` | 32 MB | Max message size |
| `k_max_args` | 200,000 | Max command arguments |
| `k_idle_timeout_ms` | 5,000 ms | Idle connection timeout |
| `k_max_load_factor` | 8 | Hash table resize trigger |
| `k_large_container_size` | 1,000 items | ZSet async delete threshold |
| `k_max_works` | 2,000 | Max expirations per cycle |
| `k_rehashing_work` | 128 | Items rehashed per operation |

## Building and Running

### Prerequisites

- C++11 compiler (g++, clang)
- POSIX-compliant system (Linux, macOS, BSD)
- pthread support

### Compilation

```bash
g++ -O2 -std=c++11 -pthread \
    14_server.cpp \
    avl.cpp hashtable.cpp heap.cpp zset.cpp thread_pool.cpp \
    -o server
```

### Execution

```bash
./server
```

Server listens on `0.0.0.0:1234` and accepts client connections.

## Testing

### Client Connection Example

Using `nc` (netcat):

```bash
nc localhost 1234
```

### Protocol Example

Send raw protocol bytes:

```
SET key value:
[0x04 0x00 0x00 0x00]  // 4 strings
[0x03 0x00 0x00 0x00] [s e t]  // "set"
[0x03 0x00 0x00 0x00] [k e y]  // "key"
[0x05 0x00 0x00 0x00] [v a l u e]  // "value"

GET key:
[0x03 0x00 0x00 0x00]  // 3 strings
[0x03 0x00 0x00 0x00] [g e t]  // "get"
[0x03 0x00 0x00 0x00] [k e y]  // "key"
```

## Performance Characteristics

### Time Complexity Summary

| Operation | Time |
|-----------|------|
| Get/Set string | O(1) amortized |
| Delete key | O(1) amortized |
| Expire/TTL | O(log N) / O(1) |
| ZAdd/ZRem | O(log N) |
| ZScore (by name) | O(1) |
| ZQuery (range) | O(log N + K) |
| Keys listing | O(N) |

### Space Complexity

- Hash tables: O(N) where N = number of keys
- AVL trees: O(M) where M = total zset elements
- Heap: O(P) where P = keys with TTL
- Buffers: O(B) where B = typical message size

## Design Patterns

### 1. Intrusive Data Structures
Nodes contain pointers enabling membership in multiple containers simultaneously:
- `HNode` in `Entry` for hash table membership
- `AVLNode` in `ZNode` for tree membership
- `HNode` in `ZNode` for zset hash membership
- `DList` in `Conn` for idle list membership

### 2. Progressive Rehashing
Hash table uses two tables during resize:
- Older table: being migrated
- Newer table: receiving migrated items
- 128 items migrated per operation
- Readers check both tables transparently

### 3. Dual Indexing
Sorted sets maintain two complementary indexes:
- AVL tree for ordered access
- Hash table for fast lookups
- Updates propagate to both structures

### 4. Non-Blocking I/O
All socket operations are non-blocking:
- `EAGAIN` handled gracefully
- State machine tracks read/write readiness
- `poll()` multiplexes thousands of connections

### 5. Async Heavy Lifting
Large operations offloaded to thread pool:
- Deletion of sorted sets >1000 items
- Prevents main loop stalls
- Main loop continues processing requests

## File Structure

| File | Lines | Purpose |
|------|-------|---------|
| `14_server.cpp` | 801 | Main event loop, protocol handling, command handlers |
| `avl.h` | 26 | AVL tree node definition and API |
| `avl.cpp` | 144 | AVL tree rotations and rebalancing |
| `hashtable.h` | 28 | Hash table node and map definitions |
| `hashtable.cpp` | 131 | Hash table implementation with progressive rehashing |
| `list.h` | 31 | Circular doubly-linked list operations |
| `heap.h` | 11 | Min-heap node definition |
| `heap.cpp` | 49 | Heap operations (up/down bubbling) |
| `zset.h` | 24 | Sorted set and node definitions |
| `zset.cpp` | 151 | Sorted set dual indexing implementation |
| `thread_pool.h` | 21 | Thread pool structure and API |
| `thread_pool.cpp` | 45 | Worker thread and queue implementation |
| `common.h` | 16 | Utility macros and hash function (FNV-1) |

## Notable Implementation Details

### Memory Management

- New/delete for dynamically allocated objects
- No explicit memory pooling (relies on allocator)
- Thread pool handles async deallocation of large structures

### Synchronization

- Single-threaded event loop (no locks needed for main data structures)
- Thread pool uses mutex + condition variable
- No locks in data structure operations (async cleanup only)

### Error Handling

- No exceptions (standard C++ style)
- Functions return error codes or status flags
- Connection closure on protocol errors

### Pipelining Support

- Multiple requests in one connection
- Response queue prevents command ordering issues
- `buf_consume()` enables incremental parsing

## Limitations

- Single-threaded main loop (scalability limited to one CPU core)
- No persistence (in-memory only)
- No authentication or encryption
- No cluster support
- No index structures beyond zset

## Future Enhancements

1. **Async I/O**: Move to epoll/kqueue for better scalability
2. **RDB Persistence**: Snapshot-based durability
3. **Replication**: Master-replica architecture
4. **Authentication**: TLS and username/password support
5. **Additional Data Types**: Lists, sets, hashes
6. **Pub/Sub**: Publish-subscribe messaging
7. **Transactions**: MULTI/EXEC support
8. **Cluster**: Distributed hash slots

## References

### Key Concepts

- **AVL Trees**: Self-balancing binary search trees with O(log N) operations
- **Hash Tables with Chaining**: Open addressing hash tables with collision handling
- **Min-Heaps**: Priority queues for efficient minimum element tracking
- **Non-blocking I/O**: Asynchronous I/O multiplexing with `poll()`
- **Intrusive Data Structures**: Memory-efficient container designs

### Standards Used

- POSIX socket API
- C++11 standard library (vector, string, deque)
- POSIX threads (pthread)

---

**Author:** Original Implementation
**License:** Open Source
**Language:** C++11
**Platform:** POSIX (Linux, macOS, BSD)
