.PHONY: build run test clean lint

BINARY=atum
BUILD_DIR=bin

build:
	go build -o $(BUILD_DIR)/$(BINARY) ./cmd/atum

run: build
	./$(BUILD_DIR)/$(BINARY) serve

test:
	go test ./... -v -race

clean:
	rm -rf $(BUILD_DIR)

lint:
	golangci-lint run ./...
