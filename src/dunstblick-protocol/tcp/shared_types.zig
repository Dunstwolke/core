pub const State = union(enum) {
    initiate_handshake,
    acknowledge_handshake,
    authenticate_info,
    authenticate_result,
    connect_header,
    connect_response,
    connect_response_item: usize,
    resource_request,
    resource_header,
    established,
};

