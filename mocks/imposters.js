module.exports = {
  imposters: [
    {
      port: 3101,
      protocol: "http",
      name: "users",
      stubs: [
        {
          predicates: [{ equals: { method: "GET", path: "/users/42" } }],
          responses: [
            {
              is: {
                statusCode: 200,
                headers: { "Content-Type": "application/json" },
                body: { id: 42, name: "Zaphod" },
              },
            },
          ],
        },
      ],
    },
  ],
};
