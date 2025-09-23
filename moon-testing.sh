#!/bin/bash

# Moon Testing Automation Scripts
# Usage: ./moon-testing.sh start|stop|status

# Requires: doctl, kubectl, helm, bun

# Configuration - Modify these as needed
CLUSTER_ID="6f7f5549-3589-4632-a008-f367d4ca8296"
NODE_POOL_NAME="moon-pool"
NODE_SIZE="s-4vcpu-8gb-intel"
DESIRED_NODES=1  # Number of nodes to create/maintain when starting
MAX_NODES=4      # Maximum nodes for reference (not used for autoscaling)

start_testing() {
    echo "🚀 Starting Moon testing environment..."
    
    # Check if node pool exists, create if not
    if doctl kubernetes cluster node-pool list $CLUSTER_ID | grep -q $NODE_POOL_NAME; then
        CURRENT_COUNT=$(doctl kubernetes cluster node-pool list $CLUSTER_ID --format "Name,Count" --no-header | grep $NODE_POOL_NAME | awk '{print $2}')
        echo "Node pool '$NODE_POOL_NAME' already exists with $CURRENT_COUNT nodes"
        
        if [ "$CURRENT_COUNT" -lt "$DESIRED_NODES" ]; then
            echo "Scaling node pool from $CURRENT_COUNT to $DESIRED_NODES nodes..."
            doctl kubernetes cluster node-pool update $CLUSTER_ID $NODE_POOL_NAME --count=$DESIRED_NODES
        else
            echo "Node pool already has sufficient nodes ($CURRENT_COUNT >= $DESIRED_NODES)"
        fi
    else
        echo "Creating node pool with $DESIRED_NODES nodes..."
        doctl kubernetes cluster node-pool create $CLUSTER_ID \
            --name $NODE_POOL_NAME \
            --size $NODE_SIZE \
            --count $DESIRED_NODES
    fi

    # Wait for nodes to be ready
    echo "Waiting for $DESIRED_NODES nodes to be ready..."
    TIMEOUT=300  # 5 minutes timeout
    ELAPSED=0
    while [ $(kubectl get nodes --no-headers | grep "Ready" | wc -l) -lt $DESIRED_NODES ]; do
        echo "Waiting for nodes... ($ELAPSED/${TIMEOUT}s)"
        sleep 10
        ELAPSED=$((ELAPSED + 10))
        if [ $ELAPSED -ge $TIMEOUT ]; then
            echo "❌ Timeout waiting for nodes to be ready"
            echo "Current node status:"
            kubectl get nodes
            exit 1
        fi
    done

    echo "✅ Nodes are ready!"
    kubectl get nodes

    # Create moon namespace if it doesn't exist
    echo "Ensuring moon namespace exists..."
    kubectl create namespace moon --dry-run=client -o yaml | kubectl apply -f -

    # Check if Moon is already installed
    if helm list -n moon | grep -q "moon"; then
        echo "Moon is already installed, checking pods..."
    else
        echo "Installing Moon..."
        # Add helm repo if not exists
        helm repo add aerokube https://charts.aerokube.com/ 2>/dev/null || true
        helm repo update

        # Install Moon
        helm upgrade --install -n moon moon aerokube/moon2 \
            --set browsers.default.selenium.chrome.repository=quay.io/browser/chromium \
            --set browsers.default.selenium.firefox.repository=quay.io/browser/firefox
    fi

    # Wait for Moon pods to be ready
    echo "Waiting for Moon pods to be ready..."
    kubectl wait --for=condition=ready pod -l app=moon -n moon --timeout=300s

    echo "🎉 Moon is ready!"
    echo "Starting port-forward to access Selenium Grid..."
    echo "Selenium Grid URL: http://localhost:4444/wd/hub"
    echo "Press Ctrl+C to stop port-forward when done testing"

    # Start port-forward in background and keep script running
    kubectl port-forward -n moon svc/moon 4444:4444 &
    PORT_FORWARD_PID=$!

    echo "Port-forward started (PID: $PORT_FORWARD_PID)"
    echo "Run './moon-testing.sh stop' in another terminal when done"

    # Keep the script running
    wait $PORT_FORWARD_PID
}

stop_testing() {
    echo "🛑 Stopping Moon testing environment..."
    
    # Kill any port-forward processes
    pkill -f "kubectl port-forward.*moon.*4444" || true
    
    # Scale node pool to 0 instead of deleting (DO requires at least 1 node pool)
    echo "Scaling node pool to 0 to save costs..."
    doctl kubernetes cluster node-pool update $CLUSTER_ID $NODE_POOL_NAME --count=0
    
    echo "✅ Testing environment stopped. Costs reduced to \$0/hour"
    echo "Moon configuration remains in cluster for next time"
    echo "Note: Node pool still exists but scaled to 0 nodes"
}

status_testing() {
    echo "📊 Moon Testing Status"
    echo "====================="
    
    # Check nodes
    NODE_COUNT=$(kubectl get nodes --no-headers 2>/dev/null | wc -l || echo "0")
    echo "Nodes: $NODE_COUNT"
    
    if [ "$NODE_COUNT" -gt 0 ]; then
        kubectl get nodes
        echo ""
        
        # Check Moon pods
        echo "Moon Pods:"
        kubectl get pods -n moon 2>/dev/null || echo "Moon namespace not found"
        echo ""
        
        # Check if port-forward is running
        if pgrep -f "kubectl port-forward.*moon.*4444" > /dev/null; then
            echo "✅ Port-forward active: http://localhost:4444/wd/hub"
        else
            echo "❌ Port-forward not active. Run: kubectl port-forward -n moon svc/moon 4444:4444"
        fi
    else
        echo "❌ No nodes available. Run './moon-testing.sh start' to begin testing"
    fi
    
    # Check DO node pool
    echo ""
    echo "DigitalOcean Node Pools:"
    doctl kubernetes cluster node-pool list $CLUSTER_ID
}

quick_test() {
    echo "🧪 Running quick connectivity test with Bun/JavaScript..."
    
    # Ensure port-forward is running
    if ! pgrep -f "kubectl port-forward.*moon.*4444" > /dev/null; then
        echo "Starting port-forward..."
        kubectl port-forward -n moon svc/moon 4444:4444 &
        sleep 3
    fi
    
    # Create temporary test script
    cat > /tmp/moon-test.js << 'EOF'
const { Builder, By, until } = require('selenium-webdriver');
const chrome = require('selenium-webdriver/chrome');

async function testMoon() {
    let driver;
    try {
        console.log("Connecting to Moon at http://localhost:4444/wd/hub...");
        
        const options = new chrome.Options();
        options.addArguments('--no-sandbox');
        options.addArguments('--disable-dev-shm-usage');
        options.addArguments('--headless');
        
        driver = await new Builder()
            .forBrowser('chrome')
            .setChromeOptions(options)
            .usingServer('http://localhost:4444/wd/hub')
            .build();
        
        await driver.get('https://www.google.com');
        const title = await driver.getTitle();
        console.log(`✅ Success! Page title: ${title}`);
        console.log("Moon is working correctly!");
        
    } catch (error) {
        console.log(`❌ Test failed: ${error.message}`);
        console.log("Make sure Moon is running and port-forward is active");
        process.exit(1);
    } finally {
        if (driver) {
            await driver.quit();
        }
    }
}

testMoon();
EOF
    
    # Run the test with bun
    bun run /tmp/moon-test.js
    
    # Clean up
    rm -f /tmp/moon-test.js
}

scale_nodes() {
    local target_count=$1
    
    if [ -z "$target_count" ] || ! [[ "$target_count" =~ ^[0-9]+$ ]]; then
        echo "❌ Error: Please provide a valid number of nodes"
        echo "Usage: $0 scale <number>"
        echo "Example: $0 scale 2"
        exit 1
    fi
    
    if [ "$target_count" -gt "$MAX_NODES" ]; then
        echo "⚠️  Warning: Requested $target_count nodes exceeds MAX_NODES ($MAX_NODES)"
        echo "This may incur higher costs. Continue? (y/N)"
        read -r confirm
        if [ "$confirm" != "y" ] && [ "$confirm" != "Y" ]; then
            echo "Cancelled."
            exit 0
        fi
    fi
    
    echo "🔄 Scaling node pool to $target_count nodes..."
    
    if doctl kubernetes cluster node-pool list $CLUSTER_ID | grep -q $NODE_POOL_NAME; then
        doctl kubernetes cluster node-pool update $CLUSTER_ID $NODE_POOL_NAME --count=$target_count
        echo "✅ Node pool scaled to $target_count nodes"
        
        if [ "$target_count" -gt 0 ]; then
            echo "Waiting for nodes to be ready..."
            while [ $(kubectl get nodes --no-headers | grep "Ready" | wc -l) -lt $target_count ]; do
                echo "Waiting for nodes..."
                sleep 10
            done
            echo "✅ All nodes are ready!"
            kubectl get nodes
        fi
    else
        echo "❌ Node pool '$NODE_POOL_NAME' not found"
        echo "Run './moon-testing.sh start' first to create the node pool"
        exit 1
    fi
}

case "$1" in
    start)
        start_testing
        ;;
    stop)
        stop_testing
        ;;
    status)
        status_testing
        ;;
    test)
        quick_test
        ;;
    scale)
        scale_nodes "$2"
        ;;
    *)
        echo "Usage: $0 {start|stop|status|test|scale}"
        echo ""
        echo "Commands:"
        echo "  start         - Create nodes and start Moon (costs money)"
        echo "  stop          - Scale nodes to 0 and stop Moon (saves money)"
        echo "  status        - Check current status"
        echo "  test          - Run a quick connectivity test"
        echo "  scale <num>   - Scale node pool to specific number of nodes"
        echo ""
        echo "Example workflow:"
        echo "  ./moon-testing.sh start    # Start testing environment with 1 node"
        echo "  ./moon-testing.sh scale 3  # Scale up to 3 nodes for heavy testing"
        echo "  ./moon-testing.sh test     # Verify it's working"
        echo "  # Run your actual tests here"
        echo "  ./moon-testing.sh stop     # Stop and save money"
        exit 1
        ;;
esac