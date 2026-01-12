package org.muralis.service.repository;

import lombok.RequiredArgsConstructor;
import org.muralis.service.model.DirectMessage;
import org.springframework.jdbc.core.JdbcTemplate;
import org.springframework.stereotype.Repository;

@Repository
@RequiredArgsConstructor
public class DirectMessageRepository {

    private final JdbcTemplate jdbcTemplate;

    public boolean existsByMessageId(String messageId) {
        String sql = "SELECT COUNT(*) FROM direct_messages WHERE message_id = ?";
        Integer count = jdbcTemplate.queryForObject(sql, Integer.class, messageId);
        return count != null && count > 0;
    }

    public void save(DirectMessage message) {
        String sql = "INSERT INTO direct_messages (city, country, message_id, "
                + "received_at) VALUES (?, ?, ?, ?)";
        jdbcTemplate.update(sql, message.getCity(), message.getCountry(),
                message.getMessageId(), message.getReceivedAt());
    }
}
