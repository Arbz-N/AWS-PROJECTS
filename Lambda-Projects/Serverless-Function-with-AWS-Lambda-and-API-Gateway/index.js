// Basic Lambda handler — returns a simple JSON response

exports.handler = async (event) => {
    // Log the incoming event — visible in CloudWatch Logs
    console.log('Event received:', JSON.stringify(event));

    const response = {
        statusCode: 200,
        body: JSON.stringify('Hello from Lambda!'),
    };

    return response;
};