CXX = g++
CXXFLAGS = -O2 -std=c++11 -pthread -Wall -Wextra
SOURCES = 14_server.cpp avl.cpp hashtable.cpp heap.cpp zset.cpp thread_pool.cpp
OBJECTS = $(SOURCES:.cpp=.o)
TARGET = server

all: $(TARGET)

$(TARGET): $(OBJECTS)
	$(CXX) $(CXXFLAGS) -o $@ $^

%.o: %.cpp
	$(CXX) $(CXXFLAGS) -c $<

clean:
	rm -f $(OBJECTS) $(TARGET)

docker-build:
	docker build -t kv-database-server:latest .

docker-run:
	docker run -d -p 1234:1234 --name kv-server kv-database-server:latest

docker-stop:
	docker stop kv-server && docker rm kv-server

docker-compose-up:
	docker-compose up -d

docker-compose-down:
	docker-compose down

.PHONY: all clean docker-build docker-run docker-stop docker-compose-up docker-compose-down
