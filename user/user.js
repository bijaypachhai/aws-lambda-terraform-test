module.exports.handler = async (event) => {
  console.log("Event: ", event);
  let responseMessage = "Hello from User A !";

  return {
    statusCode: 200,
    headers: {
      "Content-Type": "application/json",
    },
    body: JSON.stringify({
      message: responseMessage,
    }),
  };
};
