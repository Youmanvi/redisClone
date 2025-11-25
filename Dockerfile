FROM ubuntu:22.04

WORKDIR /app

RUN apt-get update && apt-get install -y \
    g++ \
    make \
    && rm -rf /var/lib/apt/lists/*

COPY *.h *.cpp ./

RUN g++ -O2 -std=c++11 -pthread \
    14_server.cpp \
    avl.cpp hashtable.cpp heap.cpp zset.cpp thread_pool.cpp \
    -o server

EXPOSE 1234

CMD ["./server"]
