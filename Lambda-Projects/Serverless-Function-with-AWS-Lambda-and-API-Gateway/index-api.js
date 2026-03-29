// Enhanced Lambda handler — works with API Gateway HTTP API
// Reads an optional ?name= query parameter from the URL

exports.handler = async (event) => {
    // API Gateway provides extra request context
    console.log('HTTP Method:', event.requestContext?.http?.method);
    console.log('Path:', event.requestContext?.http?.path);

    // Extract ?name= from query string, default to 'World' if not provided
    const name = event.queryStringParameters?.name || 'World';

    return {
        statusCode: 200,
        headers: {
            'Content-Type': 'application/json'
        },
        body: JSON.stringify({
            message: `Hello, ${name} from Lambda!`,
            timestamp: new Date().toISOString()
        })
    };
};

// Example:
// GET API_URL?name=Ali
// Response: {"message":"Hello, Ali from Lambda!","timestamp":"2026-03-28..."}